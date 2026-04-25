# AGENTS.md

## Mission

OmniArchive is a Phoenix/Elixir application that converts PDFs and image sources into searchable IIIF-compatible assets through ingestion, review, approval, and delivery workflows.
Preserve current end-to-end behavior unless a task explicitly changes it.

## Read first

For architecture, naming, migration, or genericization tasks, read these files first:
1. README.md
2. ARCHITECTURE.md
3. mix.exs
4. lib/omni_archive/ingestion/extracted_image.ex
5. lib/omni_archive/search.ex
6. lib/omni_archive_web/live/search_live.ex
7. lib/omni_archive_web/live/inspector_live/label.ex
8. lib/omni_archive_web/router.ex

If the repository is still mid-rename and these paths do not exist yet, use the old path equivalents until the rename is complete.

## Core rules

- Keep Ingestion, Search, IIIF delivery, Pipeline, and approval flow generic.
- Do not hardcode archaeology-only metadata or terminology in shared modules.
- Put domain-specific metadata, validation, search facets, labels, and UI copy in `OmniArchive.DomainProfiles.*`.
- Preserve current `/lab`, `/gallery`, and admin stage-gate behavior unless a task explicitly changes routes or workflow.
- Prefer additive, low-risk refactors.
- For schema changes, use additive migrations and dual-read/dual-write compatibility before removing old fields.
- Do not split services or introduce umbrella apps unless a task explicitly requires it.
- Do not add new dependencies unless explicitly required.
- Use the existing `Req` library for HTTP work.
- Do not reintroduce legacy identifiers.
- Use `OmniArchive`, `OmniArchiveWeb`, and `omni_archive` consistently.

## Phoenix and Elixir rules

- Handle authentication at the router level and pass `current_scope` where required.
- Prefer function components and LiveView over LiveComponents unless there is a clear reason.
- Use imported `<.input>` and `<.form>` helpers where available.
- Add stable DOM IDs to forms, buttons, and key interactive elements.
- Access struct fields directly.
- On changesets, use `Ecto.Changeset.get_field/2` where appropriate.
- Avoid unnecessary router aliases inside `scope`.
- Keep filenames aligned with module names and namespaces.

## Rename and migration rules

- When renaming modules or directories, update all references in code, tests, config, docs, release metadata, and CI files in the same change.
- After any namespace rename, run a repository-wide search for legacy names and fix leftovers in text files Do not edit binary assets just to change product names; update nearby docs or alt text instead.

## Validation

- Run relevant tests after meaningful changes.
- Before finishing, run `mix precommit`.
- Run `mix review` when the task touches architecture, validation, search, routing, schema, or wide-scope naming changes.
- If a command cannot run in the environment, report the exact failure and continue with the strongest possible validation.
