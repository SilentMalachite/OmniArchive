# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Read first

Read `AGENTS.md` before any non-trivial change — it lists the canonical "core rules",
read-first files, and the validation gate (`mix precommit`, `mix review`). Treat AGENTS.md
as authoritative; this file is the orientation layer.

Deeper context lives in: `README.md`, `ARCHITECTURE.md`, `mix.exs`,
`lib/omni_archive/ingestion/extracted_image.ex`, `lib/omni_archive/search.ex`,
`lib/omni_archive_web/live/search_live.ex`,
`lib/omni_archive_web/live/inspector_live/label.ex`, `lib/omni_archive_web/router.ex`.

## Common commands

| Task | Command |
|---|---|
| Full dev setup | `mix setup` |
| Dev server (port 4000) | `mix phx.server` |
| All tests | `mix test` |
| Single test file / line | `mix test test/path/to/file_test.exs[:42]` |
| Pre-commit gate | `mix precommit` (compile --warnings-as-errors, deps.unlock --unused, format, test) |
| Review gate | `mix review` (db version, --warnings-as-errors, credo --strict, sobelow, dialyzer) |
| Reset DB | `mix ecto.reset` |
| Prod assets | `MIX_ENV=prod mix assets.deploy` (must run **after** `mix compile`) |
| OTP release | `MIX_ENV=prod mix release` |

Run `mix review` for changes touching architecture, validation, search, routing, schema,
or wide-scope naming. OS-level tooling required: `libvips`, `poppler-utils` (`pdftoppm`),
PostgreSQL 15+, Node/npm.

## Architecture

OmniArchive is a **modular monolith** (Phoenix/Elixir + PostgreSQL) that ingests PDFs,
lets a human crop figures, and serves them as IIIF v3.0 assets. Three top-level concerns
share one codebase but have hard module boundaries:

- **Ingestion** — `OmniArchive.Ingestion`. PDF upload → `pdftoppm` chunked conversion
  (10-page chunks, 300 DPI) → manual polygon crop → libvips PTIF generation. Schemas:
  `PdfSource`, `ExtractedImage`, `ExtractedImageMetadata`.
- **Search** — `OmniArchive.Search`. PostgreSQL full-text search (tsvector + GIN) over
  captions, with faceted filtering driven by the active domain profile.
- **Delivery** — `OmniArchive.IIIF` + `OmniArchiveWeb.IIIF.*`. IIIF Image API v3.0
  (dynamic tiles from PTIF) and Presentation API v3.0 (`/iiif/manifest/:id`,
  `/iiif/presentation/:source_id/manifest`).

### Stage-gate workflow

Internal work (`/lab`) is separated from public publishing (`/gallery`). Items move
`wip → pending_review → returned/approved`. PTIF generation is **lazy** — only at admin
approval. Public projects are protected via soft-delete (`deleted_at`, with
`/admin/trash`). The Lab is a 5-step LiveView wizard
(`lib/omni_archive_web/live/inspector_live/`): `upload → browse → crop → label → finalize`.
Crop uses a **Write-on-Action** policy — no DB record until the polygon is committed.

### Domain profiles (genericness contract)

Domain-specific metadata, validation, search facets, labels, and UI copy must NOT live
in shared modules. They go in `OmniArchive.DomainProfiles.*`, implementing the
`OmniArchive.DomainProfile` behaviour (`metadata_fields/0`, `validation_rules/0`,
`search_facets/0`, `ui_texts/0`, `duplicate_identity/0`). Active profile is set in config:

```elixir
config :omni_archive, domain_profile: OmniArchive.DomainProfiles.Archaeology
```

Built-in: `Archaeology` (default), `GeneralArchive`. A YAML-driven profile
(`OmniArchive.DomainProfiles.Yaml`) is enabled when `OMNI_ARCHIVE_PROFILE_YAML` points to
a YAML file; this also starts `YamlCache` (ETS-backed GenServer) at boot. See `PROFILES.md`.

### OTP background processing

PDF processing runs off the LiveView socket via per-user `UserWorker` GenServers:

- `UserWorkerRegistry` (unique keys) + `UserWorkerSupervisor` (DynamicSupervisor,
  `:one_for_one`) — see `lib/omni_archive/application.ex`.
- `Pipeline.Pipeline` orchestrates batches with `Task.async_stream`;
  `Pipeline.ResourceMonitor` adjusts concurrency (memory guard <20% free; 1 core reserved
  for UI).
- libvips is globally constrained at app start: `concurrency_set(1)`, `cache_set_max(100)`,
  `cache_set_max_mem(512MB)`. Concurrency is managed in Elixir; libvips runs
  single-threaded. Do not change without understanding the 2GB-VPS memory budget.
- Each PDF job uses a unique temp dir (`omniarchive_job_{uuid}`) with `try/after` cleanup.

### Auth and scoping

`phx.gen.auth` session-based auth with RBAC (`admin` / `user`). Authentication is handled
at the **router level** — pass `current_scope` into LiveViews/controllers. `PdfSource`
has `user_id`; non-admin users only see their own projects. `ExtractedImage` also tracks
`owner_id` / `worker_id`. Public registration is disabled (invitation/admin-create model).

### Naming convention

Use `OmniArchive` (app), `OmniArchiveWeb` (web), `omni_archive` (OTP app / config key)
consistently. When renaming further, update code, tests, config, docs, release metadata,
and CI in the same change, then grep for legacy strings in text files (skip binary assets;
update nearby docs/alt text instead).

## Conventions worth knowing

- **Additive migrations only.** Add fields with dual-read/dual-write before removing old ones.
- **No new dependencies** unless required. Use the existing `Req` library for HTTP.
- **No umbrella split.** Keep the monolith.
- **LiveView over LiveComponent** unless clearly justified. Use imported `<.input>` /
  `<.form>` helpers; put stable DOM IDs on forms, buttons, and key interactive elements.
- **Access struct fields directly**; on changesets prefer `Ecto.Changeset.get_field/2`.
- **Keep filenames aligned with module names and namespaces.**
- Custom mix tasks for the review pipeline live in `lib/mix/tasks/`
  (`review.check_db_version`, `review.summary`).
