// deno-lint-ignore-file no-explicit-any
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { DOMParser } from "https://deno.land/x/deno_dom/deno-dom-wasm.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function normalizeUrl(input: string): string {
  try {
    const u = new URL(input);
    u.hash = "";
    ["utm_source","utm_medium","utm_campaign","utm_term","utm_content","fbclid","gclid"].forEach(p => u.searchParams.delete(p));
    return u.toString();
  } catch {
    return input;
  }
}

async function canonicalFromUrl(url: string): Promise<string | undefined> {
  try {
    const res = await fetch(url, { redirect: 'follow' });
    const html = await res.text();
    const doc = new DOMParser().parseFromString(html, 'text/html');
    const link = doc?.querySelector('link[rel="canonical"]')?.getAttribute('href');
    if (link) return new URL(link, res.url || url).toString();
    return res.url || url;
  } catch {
    return url;
  }
}

export default async function handler(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const { url, canonical_url } = await req.json();
    let canonical = canonical_url as string | undefined;
    if (!canonical && url) canonical = await canonicalFromUrl(url);
    if (!canonical) return new Response(JSON.stringify({ error: 'url or canonical_url required' }), { status: 400, headers: { 'content-type': 'application/json', ...cors } });
    canonical = normalizeUrl(canonical);

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, serviceKey);

    // Bypass RLS to check across all rows within the project
    const { data, error } = await supabase
      .from('articles')
      .select('id', { count: 'exact', head: true })
      .eq('canonical_url', canonical);
    if (error) throw error;
    const exists = (data as any)?.length === 0 ? false : true; // head:true returns empty array
    return new Response(JSON.stringify({ exists, canonical_url: canonical }), { headers: { 'content-type': 'application/json', ...cors } });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: { 'content-type': 'application/json', ...cors } });
  }
}

if (import.meta.main) {
  Deno.serve(handler);
}

