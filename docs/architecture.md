## Architecture Overview

- Flutter app (mobile/web/desktop) using Supabase for Auth and DB sync
- Offline-first via Drift (SQLite) cache and background sync
- Supabase Edge Functions for URL metadata extraction and dedupe pre-check
- Postgres FTS (GIN index) for server-side search; SQLite FTS5 offline
- Simple team role model with RLS (viewer/editor/owner)

### Data Model (Core)

- `articles`: core article metadata (title, url, canonical_url, excerpt, description, published_at, media)
- `media`: media outlet catalog with `type` enum (online/print/tv/radio/social)
- `authors`, `people`, `organizations`: entity catalogs
- Junctions: `articles_authors`, `articles_people`, `articles_organizations`

### Sync Model

- Client writes to local DB first; mark rows `dirty = true` (local only).
- Sync up uses Supabase upsert; sync down queries `updated_at > last_sync_at`.

### Search

- Server: `articles.search_vector` + GIN; `search_articles(q)` helper
- Client: FTS5 virtual table (if available) else `LIKE`fallback

