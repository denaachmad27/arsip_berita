# Arsip Berita App

Monorepo Flutter + Supabase (Postgres + Auth + Storage + Edge Functions) for archiving news articles with offline-first support and full‑text search.

## Features

- Email login (Supabase Auth)
- Article archive form: Nama Media, Jenis Media, Penulis, Tanggal, Tokoh, Organisasi, Link, Deskripsi
- Auto-extract URL metadata (title, og, canonical, excerpt) via Edge Function
- Dedupe by `canonical_url` (unique + Edge Function precheck)
- Full‑text search (Postgres FTS); offline search (SQLite/Drift)
- Tagging people/organizations (many‑to‑many)
- Offline‑first: local cache (Drift), sync to Supabase
- Export CSV/JSON
- Simple roles: Owner/Editor/Viewer via RLS

## Repository Structure

- `apps/arsip_berita_app/` – Flutter app (mobile + web + desktop)
- `supabase/migrations/` – SQL schema, FTS, RLS policies
- `supabase/functions/` – Edge Functions (`extract-metadata`, `dedupe-check`)
- `docs/` – Architecture, API, schema
- `.github/workflows/ci.yml` – CI for lint, test, and build web

## Prerequisites

- Flutter 3.22+
- GitHub repo (for CI)

## Setup (SQLite-Only Offline Mode)

This repo is configured to run without Supabase. Data is stored locally in SQLite (via sqflite) on mobile/desktop. On web, metadata extraction may be blocked by CORS.

1) Flutter app
- From `apps/arsip_berita_app`: `flutter pub get`
- Run app (Android/iOS/macOS/Windows/Linux): `flutter run`
- Web note: Metadata extraction from third-party sites may fail due to browser CORS.

## Metadata Extraction

- Done locally in-app via HTTP fetch + HTML parsing (no backend).

## Roles

- In offline mode there is no authentication/roles. All data is local to device.

## Export

- From the Articles list, use Export menu to save CSV/JSON (downloads on web, share on mobile).

## CI

- On push/PR: format, analyze, test, and build web app artifact.

## Notes

- Offline-only: the app stores data locally (in-memory placeholder now). You can switch to Drift/SQLite for durable storage.
- Search: local LIKE search currently, can be upgraded to SQLite FTS5.
