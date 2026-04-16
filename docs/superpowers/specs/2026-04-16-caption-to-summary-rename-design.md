# Design: `caption` → `summary` Rename (IIIF v3.0 Conformance)

## Background

OmniArchive uses `caption` as a core field name, but this corresponds to the IIIF Presentation API v3.0 `summary` property. This rename unifies the internal naming with the IIIF standard.

**Precondition:** `mix ecto.reset` will be run. No data migration is needed.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Approach | Full one-pass rename | Clean, consistent; `mix ecto.reset` makes it safe |
| CSS class names | Rename to `summary` | Avoid future grep confusion |
| `@reserved_keys` | Replace `caption` with `summary` | Core field conflict prevention |
| YAML fixture file names | Rename | Full consistency |
| FTS index | Drop old + create new in new migration | Keep migration history intact |
| Japanese label | "サマリー" | Matches IIIF `summary` in katakana |
| Existing migrations | Leave unchanged | New migration applies rename on top |

## Scope

### 1. Migration

**New file:** `priv/repo/migrations/20260416090000_rename_caption_to_summary.exs`

```elixir
def change do
  rename table(:extracted_images), :caption, to: :summary

  # Recreate FTS index with new column name
  execute(
    "DROP INDEX IF EXISTS idx_extracted_images_caption_fts",
    "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_extracted_images_caption_fts ON extracted_images USING gin(to_tsvector('simple', coalesce(caption, '')))"
  )

  execute(
    "CREATE INDEX IF NOT EXISTS idx_extracted_images_summary_fts ON extracted_images USING gin(to_tsvector('simple', coalesce(summary, '')))",
    "DROP INDEX IF EXISTS idx_extracted_images_summary_fts"
  )
end
```

### 2. Schema / Changeset

**`lib/omni_archive/ingestion/extracted_image.ex`:**
- `field :caption, :string` → `field :summary, :string`
- Update `cast` / `validate_required` lists: `:caption` → `:summary`

**`lib/omni_archive/ingestion/extracted_image_metadata.ex`:**
- Update any `:caption` references in metadata field mappings to `:summary`

### 3. Ingestion / Pipeline (IIIF summary mapping)

**`lib/omni_archive/ingestion.ex`** and **`lib/omni_archive/pipeline/pipeline.ex`:**
- Current: `"summary" => %{"en" => [extracted_image.caption || ""], "ja" => [extracted_image.caption || ""]}`
- After: `"summary" => %{"en" => [extracted_image.summary || ""], "ja" => [extracted_image.summary || ""]}`

The IIIF `summary` key already exists; only the source field reference changes.

### 4. Domain Profiles

**`lib/omni_archive/domain_profiles/archaeology.ex`:**
- `field: :caption` → `field: :summary`
- `validation_rules` key `caption:` → `summary:`
- Japanese label: "キャプション" → "サマリー"

**`lib/omni_archive/domain_profiles/general_archive.ex`:**
- Same changes as archaeology.ex

**`lib/omni_archive/domain_profiles/yaml_loader.ex`:**
- `@core_allowed_fields ~w[caption label]` → `~w[summary label]`
- `ensure_core_fields_present`: `[:caption, :label]` → `[:summary, :label]`

### 5. Validation

**`lib/omni_archive/domain_metadata_validation.ex`:**
- Update any `:caption` / `"caption"` references to `:summary` / `"summary"`

### 6. Search

**`lib/omni_archive/search.ex`:**
- tsvector query: `e.caption` → `e.summary`
- ilike query: `e.caption` → `e.summary`

### 7. IIIF Manifest

**`lib/omni_archive/iiif/manifest.ex`:**
- Simplify `caption → summary` mapping to direct `summary` reference

### 8. Custom Metadata Fields

**`lib/omni_archive/custom_metadata_fields/custom_metadata_field.ex`:**
- `@reserved_keys`: replace `"caption"` with `"summary"`

### 9. LiveView (6 files)

| File | Changes |
|---|---|
| `inspector_live/label.ex` | assigns `:caption` → `:summary`, params `"caption"` → `"summary"`, HTML id/name/class, `field_value`/`assign_field_value`/`auto_save_attrs` guards |
| `inspector_live/finalize.ex` | `.caption` → `.summary`, Japanese label update |
| `search_live.ex` | `.caption` → `.summary`, CSS class `result-card-caption` → `result-card-summary` |
| `gallery_live.ex` | `.caption` → `.summary`, CSS class update |
| `approval_live.ex` | `.caption` → `.summary`, CSS class `approval-card-caption` → `approval-card-summary` |
| `admin/review_live.ex` | `.caption` → `.summary`, Japanese label update |

**HTML attribute changes:**
- `id="caption-input"` → `id="summary-input"`
- `name="caption"` → `name="summary"`
- `phx-value-field="caption"` → `phx-value-field="summary"`

**Japanese UI text:**
- "キャプション" → "サマリー"
- "（キャプションなし）" → "（サマリーなし）"

### 10. CSS

Update class names in LiveView templates and CSS files:
- `result-card-caption` → `result-card-summary` (template + `assets/css/gallery.css:243`)
- `duplicate-card-caption` → `duplicate-card-summary` (template + `assets/css/inspector.css:843`)
- `approval-card-caption` → `approval-card-summary` (template; check `assets/css/` for definition)

**CSS files to update:**
- `assets/css/gallery.css` — `.result-card-caption` class definition
- `assets/css/inspector.css` — `.duplicate-card-caption` class definition

### 11. YAML Profile

**`priv/profiles/example_profile.yaml`:**
- `field: caption` → `field: summary`
- `label: "キャプション"` → `label: "サマリー"`
- `validation_rules` key `caption:` → `summary:`

### 12. Tests

**Test files (all `caption` → `summary` in data/assertions):**
- `test/omni_archive/ingestion_test.exs`
- `test/omni_archive/ingestion/extracted_image_test.exs`
- `test/omni_archive/domain_profiles/general_archive_test.exs`
- `test/omni_archive/domain_profiles/yaml_cache_test.exs`
- `test/omni_archive/domain_profiles/yaml_loader_test.exs`
- `test/omni_archive/custom_metadata_fields/reserved_keys_test.exs`
- `test/omni_archive/search_test.exs`
- `test/omni_archive_web/live/search_live_test.exs`
- `test/omni_archive_web/live/inspector_live/label_test.exs`
- `test/omni_archive_web/live/inspector_live/finalize_test.exs`
- `test/omni_archive_web/live/gallery_live_test.exs`
- `test/support/factory.ex`

**YAML fixture files (content + file rename):**
- `bad_missing_caption.yaml` → `bad_missing_summary.yaml`
- `bad_caption_metadata_storage.yaml` → `bad_summary_metadata_storage.yaml`
- All other fixtures: `field: caption` → `field: summary`, `validation_rules` `caption:` → `summary:`

**Test code referencing renamed fixtures:**
- `yaml_loader_test.exs`: update fixture file name strings

## Out of Scope

- Existing migration files (content unchanged)
- CHANGELOG / documentation references to `caption` as historical context
- Data migration (not needed with `mix ecto.reset`)

## Constraints

- Migration uses `Ecto.Migration.rename/3` only (no column create/drop)
- `storage: "core"` allowed fields: `summary` and `label` only
- Lab / Gallery / Admin workflows must remain functional
- Archaeology / GeneralArchive profiles must work without YAML profile configured
- `down` migration: reverse rename (summary → caption) + index restoration

## Verification

Execute in order:

```bash
mix ecto.reset
mix test
mix review
grep -r "caption" lib/ priv/ test/ --include="*.ex" --include="*.exs" --include="*.yaml"
```

**Completion criteria:**
1. `mix ecto.reset` + `mix ecto.migrate` succeeds
2. No `caption` field references remain in codebase
3. `mix test` passes
4. `mix review` passes (no compile warnings, credo strict, sobelow, dialyzer)
5. IIIF Manifest outputs `summary` correctly
6. Both YAML and built-in profiles work correctly
