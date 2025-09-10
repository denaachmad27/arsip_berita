// deno-lint-ignore-file no-explicit-any
import { DOMParser, Element } from "https://deno.land/x/deno_dom/deno-dom-wasm.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function normalizeUrl(input: string): string {
  try {
    const u = new URL(input);
    u.hash = "";
    // strip common tracking params
    ["utm_source","utm_medium","utm_campaign","utm_term","utm_content","fbclid","gclid"].forEach(p => u.searchParams.delete(p));
    return u.toString();
  } catch {
    return input;
  }
}

function extract(doc: any, url: string) {
  const getMeta = (selector: string) => (doc.querySelector(selector)?.getAttribute("content") ?? undefined);
  const title = (doc.querySelector('meta[property="og:title"]')?.getAttribute("content"))
    ?? doc.querySelector('meta[name="twitter:title"]')?.getAttribute("content")
    ?? (doc.querySelector("title")?.textContent ?? undefined);

  const ogDescription = getMeta('meta[property="og:description"]') ?? getMeta('meta[name="description"]');
  const canonical = (doc.querySelector('link[rel="canonical"]') as Element | null)?.getAttribute("href") ?? undefined;
  const paragraphs: string[] = [];
  doc.querySelectorAll('p')?.forEach((p: any) => {
    const t = (p.textContent || '').trim();
    if (t.length > 40) paragraphs.push(t);
  });
  const excerpt = ogDescription ?? paragraphs.slice(0, 3).join(" ").slice(0, 500) || undefined;

  let canonicalUrl = canonical ? new URL(canonical, url).toString() : undefined;
  canonicalUrl = canonicalUrl ? normalizeUrl(canonicalUrl) : undefined;

  return {
    url: normalizeUrl(url),
    canonical_url: canonicalUrl,
    title: title ?? undefined,
    og_title: title ?? undefined,
    og_description: ogDescription ?? undefined,
    excerpt: excerpt ?? undefined,
  };
}

export default async function handler(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const { url } = await req.json();
    if (!url) return new Response(JSON.stringify({ error: 'url required' }), { status: 400, headers: { 'content-type': 'application/json', ...cors } });
    const res = await fetch(url, { redirect: 'follow' });
    const html = await res.text();
    const doc = new DOMParser().parseFromString(html, 'text/html');
    if (!doc) throw new Error('Failed to parse HTML');
    const data = extract(doc, res.url || url);
    return new Response(JSON.stringify(data), { headers: { 'content-type': 'application/json', ...cors } });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: { 'content-type': 'application/json', ...cors } });
  }
}

// For local supabase functions serve
// deno run --allow-net --allow-env index.ts
if (import.meta.main) {
  Deno.serve(handler);
}

