-- Extensions
create extension if not exists pgcrypto;
create extension if not exists unaccent;

-- Enum for media type
do $$ begin
  create type media_type as enum ('online','print','tv','radio','social');
exception when duplicate_object then null; end $$;

-- Memberships: simple per-user role
create table if not exists public.memberships (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','editor','viewer')),
  created_at timestamptz not null default now(),
  unique(user_id)
);

-- Media
create table if not exists public.media (
  id bigserial primary key,
  name text not null unique,
  type media_type not null,
  created_at timestamptz not null default now()
);

-- Authors / People / Organizations
create table if not exists public.authors (
  id bigserial primary key,
  name text not null unique,
  created_at timestamptz not null default now()
);

create table if not exists public.people (
  id bigserial primary key,
  name text not null unique,
  slug text unique,
  created_at timestamptz not null default now()
);

create table if not exists public.organizations (
  id bigserial primary key,
  name text not null unique,
  slug text unique,
  created_at timestamptz not null default now()
);

-- Articles
create table if not exists public.articles (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  title text not null,
  url text not null,
  canonical_url text,
  media_id bigint references public.media(id) on delete set null,
  published_at date,
  description text,
  excerpt text,
  og_title text,
  og_description text,
  og_image text,
  search_vector tsvector
);

create unique index if not exists articles_canonical_url_uniq
  on public.articles (canonical_url)
  where canonical_url is not null;

-- Junction tables
create table if not exists public.articles_authors (
  article_id uuid not null references public.articles(id) on delete cascade,
  author_id bigint not null references public.authors(id) on delete restrict,
  primary key (article_id, author_id)
);

create table if not exists public.articles_people (
  article_id uuid not null references public.articles(id) on delete cascade,
  person_id bigint not null references public.people(id) on delete restrict,
  role text,
  primary key (article_id, person_id)
);

create table if not exists public.articles_organizations (
  article_id uuid not null references public.articles(id) on delete cascade,
  organization_id bigint not null references public.organizations(id) on delete restrict,
  role text,
  primary key (article_id, organization_id)
);

-- updated_at trigger
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists trg_articles_set_updated on public.articles;
create trigger trg_articles_set_updated
before update on public.articles
for each row execute function public.set_updated_at();

-- FTS maintenance
create or replace function public.articles_tsv_update()
returns trigger language plpgsql as $$
begin
  new.search_vector :=
    setweight(to_tsvector('simple', coalesce(new.title,'')), 'A') ||
    setweight(to_tsvector('simple', coalesce(new.excerpt,'')), 'B') ||
    setweight(to_tsvector('simple', coalesce(new.description,'')), 'C');
  return new;
end $$;

drop trigger if exists trg_articles_tsv_insupd on public.articles;
create trigger trg_articles_tsv_insupd
before insert or update on public.articles
for each row execute function public.articles_tsv_update();

create index if not exists idx_articles_tsv on public.articles using gin (search_vector);

-- Search helper (obeys RLS)
create or replace function public.search_articles(q text, limit_count int default 50, offset_count int default 0)
returns setof public.articles
language sql
as $$
  select *
  from public.articles a
  where a.search_vector @@ plainto_tsquery('simple', coalesce(q,''))
  order by ts_rank_cd(a.search_vector, plainto_tsquery('simple', coalesce(q,''))) desc, a.updated_at desc
  limit limit_count offset offset_count;
$$;

-- RLS enable
alter table public.memberships enable row level security;
alter table public.media enable row level security;
alter table public.authors enable row level security;
alter table public.people enable row level security;
alter table public.organizations enable row level security;
alter table public.articles enable row level security;
alter table public.articles_authors enable row level security;
alter table public.articles_people enable row level security;
alter table public.articles_organizations enable row level security;

-- Policies: membership-gated access
-- SELECT for viewer/editor/owner
create policy if not exists sel_memberships on public.memberships
  for select using (auth.uid() = user_id);

-- For content tables, gate by existence of membership (any role)
do $$ begin
  perform 1;
  -- media
  create policy media_select on public.media for select using (
    exists(select 1 from public.memberships m where m.user_id = auth.uid())
  );
  create policy media_write on public.media for insert with check (
    exists(select 1 from public.memberships m where m.user_id = auth.uid() and m.role in ('editor','owner'))
  );
  create policy media_update on public.media for update using (
    exists(select 1 from public.memberships m where m.user_id = auth.uid() and m.role in ('editor','owner'))
  ) with check (true);
  create policy media_delete on public.media for delete using (
    exists(select 1 from public.memberships m where m.user_id = auth.uid() and m.role = 'owner')
  );

  -- authors
  create policy authors_select on public.authors for select using (
    exists(select 1 from public.memberships m where m.user_id = auth.uid())
  );
  create policy authors_write on public.authors for insert with check (
    exists(select 1 from public.memberships m where m.user_id = auth.uid() and m.role in ('editor','owner'))
  );
  create policy authors_update on public.authors for update using (
    exists(select 1 from public.memberships m where m.user_id = auth.uid() and m.role in ('editor','owner'))
  );
  create policy authors_delete on public.authors for delete using (
    exists(select 1 from public.memberships m where m.user_id = auth.uid() and m.role = 'owner')
  );

  -- people
  create policy people_select on public.people for select using (
    exists(select 1 from public.memberships m where m.user_id = auth.uid())
  );
  create policy people_write on public.people for insert with check (
    exists(select 1 from public.memberships m where m.user_id = auth.uid() and m.role in ('editor','owner'))
  );
  create policy people_update on public.people for update using (
    exists(select 1 from public.memberships m where m.user_id = auth.uid() and m.role in ('editor','owner'))
  );
  create policy people_delete on public.people for delete using (
    exists(select 1 from public.memberships m where m.user_id = auth.uid() and m.role = 'owner')
  );

  -- organizations
  create policy orgs_select on public.organizations for select using (
    exists(select 1 from public.memberships m where m.user_id = auth.uid())
  );
  create policy orgs_write on public.organizations for insert with check (
    exists(select 1 from public.memberships m where m.user_id = auth.uid() and m.role in ('editor','owner'))
  );
  create policy orgs_update on public.organizations for update using (
    exists(select 1 from public.memberships m where m.user_id = auth.uid() and m.role in ('editor','owner'))
  );
  create policy orgs_delete on public.organizations for delete using (
    exists(select 1 from public.memberships m where m.user_id = auth.uid() and m.role = 'owner')
  );

  -- articles
  create policy articles_select on public.articles for select using (
    exists(select 1 from public.memberships m where m.user_id = auth.uid())
  );
  create policy articles_insert on public.articles for insert with check (
    exists(select 1 from public.memberships m where m.user_id = auth.uid() and m.role in ('editor','owner'))
  );
  create policy articles_update on public.articles for update using (
    exists(select 1 from public.memberships m where m.user_id = auth.uid() and m.role in ('editor','owner'))
  );
  create policy articles_delete on public.articles for delete using (
    exists(select 1 from public.memberships m where m.user_id = auth.uid() and m.role = 'owner')
  );

  -- junctions
  create policy aa_select on public.articles_authors for select using (
    exists(select 1 from public.memberships m where m.user_id = auth.uid())
  );
  create policy aa_write on public.articles_authors for insert with check (
    exists(select 1 from public.memberships m where m.user_id = auth.uid() and m.role in ('editor','owner'))
  );
  create policy aa_update on public.articles_authors for update using (
    exists(select 1 from public.memberships m where m.user_id = auth.uid() and m.role in ('editor','owner'))
  );
  create policy aa_delete on public.articles_authors for delete using (
    exists(select 1 from public.memberships m where m.user_id = auth.uid() and m.role = 'owner')
  );

  create policy ap_select on public.articles_people for select using (
    exists(select 1 from public.memberships m where m.user_id = auth.uid())
  );
  create policy ap_write on public.articles_people for insert with check (
    exists(select 1 from public.memberships m where m.user_id = auth.uid() and m.role in ('editor','owner'))
  );
  create policy ap_update on public.articles_people for update using (
    exists(select 1 from public.memberships m where m.user_id = auth.uid() and m.role in ('editor','owner'))
  );
  create policy ap_delete on public.articles_people for delete using (
    exists(select 1 from public.memberships m where m.user_id = auth.uid() and m.role = 'owner')
  );

  create policy ao_select on public.articles_organizations for select using (
    exists(select 1 from public.memberships m where m.user_id = auth.uid())
  );
  create policy ao_write on public.articles_organizations for insert with check (
    exists(select 1 from public.memberships m where m.user_id = auth.uid() and m.role in ('editor','owner'))
  );
  create policy ao_update on public.articles_organizations for update using (
    exists(select 1 from public.memberships m where m.user_id = auth.uid() and m.role in ('editor','owner'))
  );
  create policy ao_delete on public.articles_organizations for delete using (
    exists(select 1 from public.memberships m where m.user_id = auth.uid() and m.role = 'owner')
  );
exception when others then null; end $$;

