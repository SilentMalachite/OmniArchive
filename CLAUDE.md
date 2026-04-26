# CLAUDE.md

Orientation map for Claude Code working in this repository.
**`AGENTS.md` is the canonical rules file** — if this document and AGENTS.md
disagree, AGENTS.md wins. Read CLAUDE.md for the architectural mental model and
"what to look at first" routing; read AGENTS.md for the rules and the
validation gate.

## Read first

1. `AGENTS.md` — core rules, preservation invariants, validation gate
2. `ARCHITECTURE.md` — module-boundary rationale
3. `PROFILES.md` — the genericness / domain-profile contract

Then route to code by task:

| Task | Start here |
|---|---|
| PDF ingestion / pipeline | `lib/omni_archive/ingestion/pdf_processor.ex`, `extracted_image.ex`, `lib/omni_archive/application.ex` |
| Search / facets | `lib/omni_archive/search.ex`, `lib/omni_archive_web/live/search_live.ex` |
| Lab wizard (5 steps) | `lib/omni_archive_web/live/inspector_live/{upload,browse,crop,label,finalize}.ex` |
| IIIF delivery | `lib/omni_archive_web/iiif/`, `lib/omni_archive/iiif/` |
| Routing / auth scoping | `lib/omni_archive_web/router.ex` |
| Domain profiles | `lib/omni_archive/domain_profile.ex`, `lib/omni_archive/domain_profiles/*.ex` |
| Custom review mix tasks | `lib/mix/tasks/review_*.ex` |

## Architecture in one breath

**Modular monolith** (Phoenix/Elixir + PostgreSQL). PDFs come in, a human crops
figures, IIIF v3.0 serves them. Three top-level concerns share the codebase but
have hard module boundaries:

- **Ingestion** (`OmniArchive.Ingestion`) — PDF upload → `pdftoppm` chunked
  conversion (10-page chunks, 300 DPI) → manual polygon crop → libvips PTIF
  generation. Schemas: `PdfSource`, `ExtractedImage`, `ExtractedImageMetadata`.
- **Search** (`OmniArchive.Search`) — PostgreSQL full-text search
  (tsvector + GIN) over captions; facets come from the active domain profile.
- **Delivery** (`OmniArchive.IIIF` + `OmniArchiveWeb.IIIF.*`) — IIIF Image API
  v3.0 (dynamic tiles from PTIF) and Presentation API v3.0
  (`/iiif/manifest/:id`, `/iiif/presentation/:source_id/manifest`).

### Stage-gate workflow

Internal work (`/lab`) is separated from public publishing (`/gallery`). Items
move `wip → pending_review → returned/approved`. **PTIF generation is lazy** —
only at admin approval. Public projects are protected via soft-delete
(`deleted_at`, surfaced in `/admin/trash`). The Lab is a 5-step LiveView wizard
in `lib/omni_archive_web/live/inspector_live/`. Crop uses a **Write-on-Action**
policy: no DB record exists until the polygon is committed.

### Domain profiles (the genericness contract)

Domain-specific metadata, validation, search facets, labels, and UI copy must
**not** live in shared modules. They go in `OmniArchive.DomainProfiles.*` and
implement `OmniArchive.DomainProfile`
(`metadata_fields/0`, `validation_rules/0`, `search_facets/0`, `ui_texts/0`,
`duplicate_identity/0`). The active profile is set in config:

```elixir
config :omni_archive, domain_profile: OmniArchive.DomainProfiles.Archaeology
```

Built-in: `Archaeology` (default), `GeneralArchive`. A YAML-driven profile
(`OmniArchive.DomainProfiles.Yaml`) activates when `OMNI_ARCHIVE_PROFILE_YAML`
points to a YAML file; this also starts `YamlCache` (ETS-backed GenServer) at
boot — see `config/runtime.exs`. Details in `PROFILES.md`.

> Before editing any shared module, ask: *"is this true for every domain?"*
> If the answer is no, the diff belongs in a DomainProfile — not in the shared
> module.

### OTP background processing

PDF jobs run off the LiveView socket via per-user `UserWorker` GenServers:

- `UserWorkerRegistry` (unique keys) + `UserWorkerSupervisor`
  (`DynamicSupervisor`, `:one_for_one`) — see `lib/omni_archive/application.ex`.
- `Pipeline.Pipeline` orchestrates batches with `Task.async_stream`;
  `Pipeline.ResourceMonitor` adjusts concurrency (memory guard <20% free; one
  core reserved for UI).
- libvips is globally constrained at app start
  (`lib/omni_archive/application.ex:12-14`): `concurrency_set(1)`,
  `cache_set_max(100)`, `cache_set_max_mem(512MB)`. Concurrency is owned by
  Elixir; libvips runs single-threaded. **Do not relax these without
  understanding the 2GB-VPS memory budget.**
- Each PDF job uses a unique temp dir (`omniarchive_job_{uuid}`) and cleans up
  via `try/after`.

### Auth and scoping

`phx.gen.auth` session-based auth with RBAC (`admin` / `user`).
**Authentication is enforced at the router level** — pass `current_scope` into
LiveViews and controllers. `PdfSource` has `user_id`; non-admin users only see
their own projects. `ExtractedImage` also tracks `owner_id` / `worker_id`.
Public registration is disabled (invitation / admin-create model).

## Invariants that bite

- **Additive migrations only.** Add fields with dual-read/dual-write before
  removing old columns.
- **No new dependencies** unless required. Use the existing `Req` library for
  HTTP work.
- **No umbrella split.** Keep the monolith.
- **LiveView over LiveComponent** unless clearly justified. Use imported
  `<.input>` / `<.form>` helpers; put stable DOM IDs on forms, buttons, and key
  interactive elements.
- **Access struct fields directly**; on changesets prefer
  `Ecto.Changeset.get_field/2`.
- **Filenames track module names and namespaces.**
- Keep `OmniArchive` / `OmniArchiveWeb` / `omni_archive` consistent. When
  renaming, update code, tests, config, docs, release metadata, and CI in the
  *same* change, then grep for legacy strings in text files (skip binary
  assets; fix nearby docs / alt text instead).

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
| Prod assets | `MIX_ENV=prod mix assets.deploy` (run **after** `mix compile`) |
| OTP release | `MIX_ENV=prod mix release` |

Run `mix review` whenever the change touches architecture, validation, search,
routing, schema, or wide-scope naming. OS-level tooling required: `libvips`,
`poppler-utils` (`pdftoppm`), PostgreSQL 15+, Node/npm.
