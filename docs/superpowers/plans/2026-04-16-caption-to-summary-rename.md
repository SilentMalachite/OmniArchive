# caption-to-summary Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the core field `caption` to `summary` across the entire codebase to align with IIIF Presentation API v3.0 naming.

**Architecture:** This is a pure rename refactor with no behavioral changes. A new Ecto migration renames the DB column, and all Elixir code, LiveView templates, CSS, YAML profiles, test fixtures, and test files are updated from `caption` to `summary`. The IIIF `summary` mapping in `ingestion.ex` and `pipeline.ex` simplifies from `"summary" => caption` to `"summary" => summary`.

**Tech Stack:** Elixir/Phoenix, Ecto, PostgreSQL, LiveView, Tailwind CSS, YAML

---

## File Map

### Files to Create
- `priv/repo/migrations/20260416090000_rename_caption_to_summary.exs`
- `test/support/yaml_fixtures/bad_missing_summary.yaml` (renamed from `bad_missing_caption.yaml`)
- `test/support/yaml_fixtures/bad_summary_metadata_storage.yaml` (renamed from `bad_caption_metadata_storage.yaml`)

### Files to Modify (lib/)
- `lib/omni_archive/ingestion/extracted_image.ex` (lines 31, 71)
- `lib/omni_archive/ingestion.ex` (lines 453-454)
- `lib/omni_archive/pipeline/pipeline.ex` (lines 423-424)
- `lib/omni_archive/domain_profiles/archaeology.ex` (lines 12, 27)
- `lib/omni_archive/domain_profiles/general_archive.ex` (lines 12, 47)
- `lib/omni_archive/domain_profiles/yaml_loader.ex` (lines 7, 97)
- `lib/omni_archive/search.ex` (lines 116, 120)
- `lib/omni_archive/custom_metadata_fields/custom_metadata_field.ex` (line 12)
- `lib/omni_archive_web/live/inspector_live/label.ex` (lines 49, 83, 162, 229, 306, 569-584, 625-626, 747, 752, 763)
- `lib/omni_archive_web/live/inspector_live/finalize.ex` (lines 221, 224)
- `lib/omni_archive_web/live/search_live.ex` (lines 173, 179-180)
- `lib/omni_archive_web/live/gallery_live.ex` (lines 315, 322-323, 377-378, 433)
- `lib/omni_archive_web/live/approval_live.ex` (lines 103, 113-114)
- `lib/omni_archive_web/live/admin/review_live.ex` (lines 352, 480, 494)

### Files to Modify (assets/)
- `assets/css/inspector.css` (line 843)
- `assets/css/gallery.css` (line 243)

### Files to Modify (priv/)
- `priv/profiles/example_profile.yaml` (lines 2, 23)

### Files to Modify (test/)
- `test/support/factory.ex` (line 50)
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
- All YAML fixtures in `test/support/yaml_fixtures/` containing `field: caption`

### Files to Delete
- `test/support/yaml_fixtures/bad_missing_caption.yaml`
- `test/support/yaml_fixtures/bad_caption_metadata_storage.yaml`

---

## Task 1: Migration

**Files:**
- Create: `priv/repo/migrations/20260416090000_rename_caption_to_summary.exs`

- [ ] **Step 1: Create the migration file**

```elixir
defmodule OmniArchive.Repo.Migrations.RenameCaptionToSummary do
  use Ecto.Migration

  def change do
    rename table(:extracted_images), :caption, to: :summary

    # Drop old FTS index
    execute(
      "DROP INDEX IF EXISTS idx_extracted_images_caption_fts",
      "CREATE INDEX IF NOT EXISTS idx_extracted_images_caption_fts ON extracted_images USING gin(to_tsvector('simple', coalesce(caption, '')))"
    )

    # Create new FTS index
    execute(
      "CREATE INDEX IF NOT EXISTS idx_extracted_images_summary_fts ON extracted_images USING gin(to_tsvector('simple', coalesce(summary, '')))",
      "DROP INDEX IF EXISTS idx_extracted_images_summary_fts"
    )
  end
end
```

- [ ] **Step 2: Verify migration compiles**

Run: `mix compile --no-start`
Expected: Compilation succeeds with no errors.

- [ ] **Step 3: Commit**

```bash
git add priv/repo/migrations/20260416090000_rename_caption_to_summary.exs
git commit -m "feat: add migration to rename caption column to summary"
```

---

## Task 2: Schema & Changeset

**Files:**
- Modify: `lib/omni_archive/ingestion/extracted_image.ex`

- [ ] **Step 1: Rename the schema field**

In `lib/omni_archive/ingestion/extracted_image.ex`, replace the field declaration (line 31):

```elixir
# Before:
    # キャプション (手動入力)
    field :caption, :string

# After:
    # サマリー (手動入力) — IIIF v3.0 summary
    field :summary, :string
```

- [ ] **Step 2: Update the changeset cast list**

In the same file, in the `changeset/2` function's `cast` list (around line 71):

```elixir
# Before:
      :caption,

# After:
      :summary,
```

- [ ] **Step 3: Verify compilation**

Run: `mix compile --no-start 2>&1 | head -50`
Expected: Compilation succeeds (warnings about caption references in other files are expected at this stage).

- [ ] **Step 4: Commit**

```bash
git add lib/omni_archive/ingestion/extracted_image.ex
git commit -m "feat: rename :caption to :summary in ExtractedImage schema"
```

---

## Task 3: Domain Profiles (Archaeology + GeneralArchive)

**Files:**
- Modify: `lib/omni_archive/domain_profiles/archaeology.ex`
- Modify: `lib/omni_archive/domain_profiles/general_archive.ex`

- [ ] **Step 1: Update Archaeology profile**

In `lib/omni_archive/domain_profiles/archaeology.ex`:

Replace `metadata_fields/0` first entry (line 12):

```elixir
# Before:
      %{
        field: :caption,
        storage: :core,
        label: "📝 キャプション（図の説明）",
        placeholder: "例: 第3図 土器出土状況"
      },

# After:
      %{
        field: :summary,
        storage: :core,
        label: "📝 サマリー（図の説明）",
        placeholder: "例: 第3図 土器出土状況"
      },
```

Replace `validation_rules/0` caption key (line 27):

```elixir
# Before:
      caption: %{
        max_length: 1000,
        max_length_error: "1000文字以内で入力してください"
      },

# After:
      summary: %{
        max_length: 1000,
        max_length_error: "1000文字以内で入力してください"
      },
```

Replace the search placeholder text referencing キャプション (in `ui_texts/0`):

```elixir
# Before:
        placeholder: "キャプション、ラベル、遺跡名で検索...",

# After:
        placeholder: "サマリー、ラベル、遺跡名で検索...",
```

- [ ] **Step 2: Update GeneralArchive profile**

In `lib/omni_archive/domain_profiles/general_archive.ex`:

Replace `metadata_fields/0` first entry (line 12):

```elixir
# Before:
      %{
        field: :caption,
        storage: :core,
        label: "📝 キャプション",
        placeholder: "例: 収蔵資料の見出しや内容説明"
      },

# After:
      %{
        field: :summary,
        storage: :core,
        label: "📝 サマリー",
        placeholder: "例: 収蔵資料の見出しや内容説明"
      },
```

Replace `validation_rules/0` caption key (line 47):

```elixir
# Before:
      caption: %{
        max_length: 1000,
        max_length_error: "1000文字以内で入力してください"
      },

# After:
      summary: %{
        max_length: 1000,
        max_length_error: "1000文字以内で入力してください"
      },
```

Replace the search placeholder text referencing キャプション (in `ui_texts/0`):

```elixir
# Before:
        placeholder: "キャプション、ラベル、コレクション名で検索...",

# After:
        placeholder: "サマリー、ラベル、コレクション名で検索...",
```

- [ ] **Step 3: Verify compilation**

Run: `mix compile --no-start 2>&1 | head -30`
Expected: Compiles successfully.

- [ ] **Step 4: Commit**

```bash
git add lib/omni_archive/domain_profiles/archaeology.ex lib/omni_archive/domain_profiles/general_archive.ex
git commit -m "feat: rename caption to summary in built-in domain profiles"
```

---

## Task 4: YamlLoader & Reserved Keys

**Files:**
- Modify: `lib/omni_archive/domain_profiles/yaml_loader.ex`
- Modify: `lib/omni_archive/custom_metadata_fields/custom_metadata_field.ex`

- [ ] **Step 1: Update YamlLoader**

In `lib/omni_archive/domain_profiles/yaml_loader.ex`:

Replace `@core_allowed_fields` (line 7):

```elixir
# Before:
  @core_allowed_fields ~w[caption label]

# After:
  @core_allowed_fields ~w[summary label]
```

Replace `ensure_core_fields_present/1` required list (line 97):

```elixir
# Before:
    required = [:caption, :label]

# After:
    required = [:summary, :label]
```

- [ ] **Step 2: Update reserved keys**

In `lib/omni_archive/custom_metadata_fields/custom_metadata_field.ex` (line 12):

```elixir
# Before:
  @reserved_keys ~w(caption label site period artifact_type collection item_type date_note)

# After:
  @reserved_keys ~w(summary label site period artifact_type collection item_type date_note)
```

- [ ] **Step 3: Verify compilation**

Run: `mix compile --no-start 2>&1 | head -30`
Expected: Compiles successfully.

- [ ] **Step 4: Commit**

```bash
git add lib/omni_archive/domain_profiles/yaml_loader.ex lib/omni_archive/custom_metadata_fields/custom_metadata_field.ex
git commit -m "feat: rename caption to summary in yaml_loader and reserved_keys"
```

---

## Task 5: Search & Ingestion/Pipeline

**Files:**
- Modify: `lib/omni_archive/search.ex`
- Modify: `lib/omni_archive/ingestion.ex`
- Modify: `lib/omni_archive/pipeline/pipeline.ex`

- [ ] **Step 1: Update Search**

In `lib/omni_archive/search.ex`, in the `apply_text_search/2` function (lines 116, 120):

```elixir
# Before (line 116):
          e.caption,

# After:
          e.summary,

# Before (line 120):
          ilike(e.caption, ^pattern) or

# After:
          ilike(e.summary, ^pattern) or
```

- [ ] **Step 2: Update Ingestion IIIF mapping**

In `lib/omni_archive/ingestion.ex` (lines 453-454):

```elixir
# Before:
                "summary" => %{
                  "en" => [image.caption || ""],
                  "ja" => [image.caption || ""]
                }

# After:
                "summary" => %{
                  "en" => [image.summary || ""],
                  "ja" => [image.summary || ""]
                }
```

- [ ] **Step 3: Update Pipeline IIIF mapping**

In `lib/omni_archive/pipeline/pipeline.ex` (lines 423-424):

```elixir
# Before:
        "summary" => %{
          "en" => [extracted_image.caption || ""],
          "ja" => [extracted_image.caption || ""]
        }

# After:
        "summary" => %{
          "en" => [extracted_image.summary || ""],
          "ja" => [extracted_image.summary || ""]
        }
```

- [ ] **Step 4: Verify compilation**

Run: `mix compile --no-start 2>&1 | head -30`
Expected: Compiles successfully.

- [ ] **Step 5: Commit**

```bash
git add lib/omni_archive/search.ex lib/omni_archive/ingestion.ex lib/omni_archive/pipeline/pipeline.ex
git commit -m "feat: rename caption to summary in search, ingestion, and pipeline"
```

---

## Task 6: LiveView — Inspector Label

**Files:**
- Modify: `lib/omni_archive_web/live/inspector_live/label.ex`

This file has the most caption references. All changes are mechanical `caption` → `summary` replacements.

- [ ] **Step 1: Update socket assigns**

Replace all `assign(:caption, ...)` with `assign(:summary, ...)`:

Line 49:
```elixir
# Before:
     |> assign(:caption, extracted_image.caption || "")
# After:
     |> assign(:summary, extracted_image.summary || "")
```

Line 83:
```elixir
# Before:
      |> assign(:caption, Map.get(params, "caption", socket.assigns.caption))
# After:
      |> assign(:summary, Map.get(params, "summary", socket.assigns.summary))
```

Line 162:
```elixir
# Before:
         |> assign(:caption, previous.caption)
# After:
         |> assign(:summary, previous.summary)
```

- [ ] **Step 2: Update snapshot and save functions**

Line 229 (take_snapshot):
```elixir
# Before:
    %{
      caption: socket.assigns.caption,
      label: socket.assigns.label,
# After:
    %{
      summary: socket.assigns.summary,
      label: socket.assigns.label,
```

Line 306 (save_metadata):
```elixir
# Before:
    base_attrs = %{
      caption: socket.assigns.caption,
      label: socket.assigns.label,
# After:
    base_attrs = %{
      summary: socket.assigns.summary,
      label: socket.assigns.label,
```

- [ ] **Step 3: Update field routing functions**

Line 747 (field_value):
```elixir
# Before:
  defp field_value(socket, field) when field in ["caption", "label"],
# After:
  defp field_value(socket, field) when field in ["summary", "label"],
```

Line 752 (assign_field_value):
```elixir
# Before:
  defp assign_field_value(socket, field, value) when field in ["caption", "label"] do
# After:
  defp assign_field_value(socket, field, value) when field in ["summary", "label"] do
```

Line 763 (auto_save_attrs):
```elixir
# Before:
  defp auto_save_attrs(_socket, field, value) when field in ["caption", "label"] do
# After:
  defp auto_save_attrs(_socket, field, value) when field in ["summary", "label"] do
```

- [ ] **Step 4: Update HTML template**

Lines 569-584 (caption input form group):
```elixir
# Before:
          <div class="form-group">
            <% caption_field = metadata_field(:caption) %>
            <label for="caption-input" class="form-label">{caption_field.label}</label>
            <input
              type="text"
              id="caption-input"
              class={["form-input form-input-large", @validation_errors[:caption] && "input-error"]}
              value={@caption}
              phx-blur="blur_save_field"
              phx-value-field="caption"
              placeholder={caption_field.placeholder}
              name="caption"
              maxlength="1000"
            />
            <%!-- キャプションエラー --%>
            <%= if @validation_errors[:caption] do %>
              <p class="field-error-text">⚠️ {@validation_errors[:caption]}</p>
            <% end %>
          </div>

# After:
          <div class="form-group">
            <% summary_field = metadata_field(:summary) %>
            <label for="summary-input" class="form-label">{summary_field.label}</label>
            <input
              type="text"
              id="summary-input"
              class={["form-input form-input-large", @validation_errors[:summary] && "input-error"]}
              value={@summary}
              phx-blur="blur_save_field"
              phx-value-field="summary"
              placeholder={summary_field.placeholder}
              name="summary"
              maxlength="1000"
            />
            <%!-- サマリーエラー --%>
            <%= if @validation_errors[:summary] do %>
              <p class="field-error-text">⚠️ {@validation_errors[:summary]}</p>
            <% end %>
          </div>
```

Lines 625-626 (duplicate card):
```elixir
# Before:
                    <span class="duplicate-card-caption">
                      {@duplicate_record.caption || "（キャプションなし）"}

# After:
                    <span class="duplicate-card-summary">
                      {@duplicate_record.summary || "（サマリーなし）"}
```

- [ ] **Step 5: Verify compilation**

Run: `mix compile --no-start 2>&1 | head -30`
Expected: Compiles successfully.

- [ ] **Step 6: Commit**

```bash
git add lib/omni_archive_web/live/inspector_live/label.ex
git commit -m "feat: rename caption to summary in inspector label LiveView"
```

---

## Task 7: LiveView — Finalize, Search, Gallery, Approval, Admin Review

**Files:**
- Modify: `lib/omni_archive_web/live/inspector_live/finalize.ex`
- Modify: `lib/omni_archive_web/live/search_live.ex`
- Modify: `lib/omni_archive_web/live/gallery_live.ex`
- Modify: `lib/omni_archive_web/live/approval_live.ex`
- Modify: `lib/omni_archive_web/live/admin/review_live.ex`

- [ ] **Step 1: Update finalize.ex**

Lines 221-224:
```elixir
# Before:
            <%= if @extracted_image.caption do %>
              <div class="confirm-item">
                <span class="confirm-label">📝 キャプション:</span>
                <span class="confirm-value">{@extracted_image.caption}</span>

# After:
            <%= if @extracted_image.summary do %>
              <div class="confirm-item">
                <span class="confirm-label">📝 サマリー:</span>
                <span class="confirm-value">{@extracted_image.summary}</span>
```

- [ ] **Step 2: Update search_live.ex**

Line 173:
```elixir
# Before:
                  alt={image.caption || "図版"}
# After:
                  alt={image.summary || "図版"}
```

Lines 179-180:
```elixir
# Before:
                  <%= if image.caption do %>
                    <p class="result-card-caption">{image.caption}</p>
# After:
                  <%= if image.summary do %>
                    <p class="result-card-summary">{image.summary}</p>
```

- [ ] **Step 3: Update gallery_live.ex**

Line 315:
```elixir
# Before:
                    alt={image.caption || "図版"}
# After:
                    alt={image.summary || "図版"}
```

Lines 322-323:
```elixir
# Before:
                  <%= if image.caption do %>
                    <p class="result-card-caption">{image.caption}</p>
# After:
                  <%= if image.summary do %>
                    <p class="result-card-summary">{image.summary}</p>
```

Lines 377-378:
```elixir
# Before:
              <%= if @selected_image.caption do %>
                <p class="text-gray-400 text-sm">{@selected_image.caption}</p>
# After:
              <%= if @selected_image.summary do %>
                <p class="text-gray-400 text-sm">{@selected_image.summary}</p>
```

Line 433:
```elixir
# Before:
                    alt={@selected_image.caption || "図版"}
# After:
                    alt={@selected_image.summary || "図版"}
```

- [ ] **Step 4: Update approval_live.ex**

Line 103:
```elixir
# Before:
                  alt={image.caption || "図版"}
# After:
                  alt={image.summary || "図版"}
```

Lines 113-114:
```elixir
# Before:
                <%= if image.caption do %>
                  <p class="approval-card-caption">{image.caption}</p>
# After:
                <%= if image.summary do %>
                  <p class="approval-card-summary">{image.summary}</p>
```

- [ ] **Step 5: Update admin/review_live.ex**

Line 352:
```elixir
# Before:
                          alt={item.image.caption || "図版"}
# After:
                          alt={item.image.summary || "図版"}
```

Line 480:
```elixir
# Before:
                  alt={@selected_image.image.caption || "図版"}
# After:
                  alt={@selected_image.image.summary || "図版"}
```

Line 494:
```elixir
# Before:
                <span class="inspector-detail-label">キャプション</span>
                <span class="inspector-detail-value">{@selected_image.image.caption || "—"}</span>
# After:
                <span class="inspector-detail-label">サマリー</span>
                <span class="inspector-detail-value">{@selected_image.image.summary || "—"}</span>
```

- [ ] **Step 6: Verify compilation**

Run: `mix compile --no-start 2>&1 | head -30`
Expected: Compiles successfully with no warnings.

- [ ] **Step 7: Commit**

```bash
git add lib/omni_archive_web/live/inspector_live/finalize.ex \
        lib/omni_archive_web/live/search_live.ex \
        lib/omni_archive_web/live/gallery_live.ex \
        lib/omni_archive_web/live/approval_live.ex \
        lib/omni_archive_web/live/admin/review_live.ex
git commit -m "feat: rename caption to summary in all remaining LiveViews"
```

---

## Task 8: CSS Files

**Files:**
- Modify: `assets/css/inspector.css`
- Modify: `assets/css/gallery.css`

- [ ] **Step 1: Update inspector.css**

At line 843:
```css
/* Before: */
.duplicate-card-caption {

/* After: */
.duplicate-card-summary {
```

- [ ] **Step 2: Update gallery.css**

At line 243:
```css
/* Before: */
.result-card-caption {

/* After: */
.result-card-summary {
```

- [ ] **Step 3: Commit**

```bash
git add assets/css/inspector.css assets/css/gallery.css
git commit -m "feat: rename caption CSS classes to summary"
```

---

## Task 9: YAML Profile & Fixtures

**Files:**
- Modify: `priv/profiles/example_profile.yaml`
- Modify: All YAML fixtures in `test/support/yaml_fixtures/` containing `field: caption`
- Create: `test/support/yaml_fixtures/bad_missing_summary.yaml` (copy from bad_missing_caption.yaml)
- Create: `test/support/yaml_fixtures/bad_summary_metadata_storage.yaml` (copy from bad_caption_metadata_storage.yaml)
- Delete: `test/support/yaml_fixtures/bad_missing_caption.yaml`
- Delete: `test/support/yaml_fixtures/bad_caption_metadata_storage.yaml`

- [ ] **Step 1: Update example_profile.yaml**

```yaml
# Before:
  - field: caption
    storage: core
    label: "キャプション"
    placeholder: "例: 表紙の写真"

# After:
  - field: summary
    storage: core
    label: "サマリー"
    placeholder: "例: 表紙の写真"
```

And in validation_rules:

```yaml
# Before:
  caption:
    max_length: 1000
    max_length_error: "1000文字以内で入力してください"

# After:
  summary:
    max_length: 1000
    max_length_error: "1000文字以内で入力してください"
```

And in ui_texts:

```yaml
# Before:
    placeholder: "キャプション、ラベル、コレクション名で検索..."

# After:
    placeholder: "サマリー、ラベル、コレクション名で検索..."
```

- [ ] **Step 2: Update all YAML fixtures that contain `field: caption`**

For each of these files, replace `field: caption` with `field: summary`:

- `test/support/yaml_fixtures/valid_minimal.yaml`
- `test/support/yaml_fixtures/valid_with_validation.yaml` (also `caption:` → `summary:` in validation_rules)
- `test/support/yaml_fixtures/valid_reserved_keys.yaml`
- `test/support/yaml_fixtures/bad_invalid_field_key.yaml`
- `test/support/yaml_fixtures/bad_ui_texts_missing.yaml`
- `test/support/yaml_fixtures/bad_core_on_other_field.yaml`
- `test/support/yaml_fixtures/bad_duplicate_fields.yaml` (has TWO `field: caption` entries — replace both)
- `test/support/yaml_fixtures/bad_missing_label.yaml`
- `test/support/yaml_fixtures/bad_duplicate_unknown_scope.yaml`
- `test/support/yaml_fixtures/bad_facet_unknown_field.yaml`
- `test/support/yaml_fixtures/bad_validation_unknown_field.yaml`
- `test/support/yaml_fixtures/bad_validation_regex.yaml`

- [ ] **Step 3: Rename and update bad_missing_caption.yaml**

Create `test/support/yaml_fixtures/bad_missing_summary.yaml` with the same content as `bad_missing_caption.yaml` (this file intentionally omits the summary field — its content has no `field: caption` since it tests the missing case, so only the file name changes).

Delete `test/support/yaml_fixtures/bad_missing_caption.yaml`.

- [ ] **Step 4: Rename and update bad_caption_metadata_storage.yaml**

Create `test/support/yaml_fixtures/bad_summary_metadata_storage.yaml` with this content:

```yaml
metadata_fields:
  - field: summary
    storage: metadata
    label: "サマリー"
    placeholder: ""
  - field: label
    storage: core
    label: "ラベル"
    placeholder: ""
  - field: collection
    storage: metadata
    label: "コレクション"
    placeholder: ""

validation_rules: {}

search_facets:
  - field: collection
    param: collection
    label: "コレクション"

duplicate_identity:
  profile_key: "test_yaml"
  scope_field: collection
  label_field: label
  duplicate_label_error: "重複"

ui_texts:
  search:
    page_title: "t"
    heading: "t"
    description: "t"
    placeholder: "t"
    empty_filtered: "t"
    empty_filtered_hint: "t"
    empty_initial: "t"
    empty_initial_hint: "t"
    result_none: "t"
    result_suffix: "t"
    clear_filters: "t"
  inspector_label:
    heading: "t"
    description: "t"
    duplicate_warning: "t"
    duplicate_blocked: "t"
    duplicate_title: "t"
    duplicate_edit: "t"
```

Delete `test/support/yaml_fixtures/bad_caption_metadata_storage.yaml`.

- [ ] **Step 5: Commit**

```bash
git add priv/profiles/example_profile.yaml test/support/yaml_fixtures/
git commit -m "feat: rename caption to summary in YAML profile and all fixtures"
```

---

## Task 10: Test Files

**Files:**
- Modify: `test/support/factory.ex`
- Modify: `test/omni_archive/ingestion_test.exs`
- Modify: `test/omni_archive/ingestion/extracted_image_test.exs`
- Modify: `test/omni_archive/domain_profiles/general_archive_test.exs`
- Modify: `test/omni_archive/domain_profiles/yaml_cache_test.exs`
- Modify: `test/omni_archive/domain_profiles/yaml_loader_test.exs`
- Modify: `test/omni_archive/custom_metadata_fields/reserved_keys_test.exs`
- Modify: `test/omni_archive/search_test.exs`
- Modify: `test/omni_archive_web/live/search_live_test.exs`
- Modify: `test/omni_archive_web/live/inspector_live/label_test.exs`
- Modify: `test/omni_archive_web/live/inspector_live/finalize_test.exs`
- Modify: `test/omni_archive_web/live/gallery_live_test.exs`

- [ ] **Step 1: Update factory.ex**

In `test/support/factory.ex` (line 50):

```elixir
# Before:
        caption: "第1図 テスト土器",

# After:
        summary: "第1図 テスト土器",
```

- [ ] **Step 2: Update ingestion_test.exs**

Replace all `caption:` atom keys and `caption` string references with `summary`:

Line 163: `caption: "テスト図版"` → `summary: "テスト図版"`
Line 169: `assert image.caption == "テスト図版"` → `assert image.summary == "テスト図版"`
Line 184: `caption: "更新されたキャプション"` → `summary: "更新されたサマリー"`
Line 188: `assert updated.caption == "更新されたキャプション"` → `assert updated.summary == "更新されたサマリー"`
Line 366: `%{caption: "新caption"}` → `%{summary: "新summary"}`
Line 371: `%{caption: "更新OK"}` → `%{summary: "更新OK"}`
Line 372: `assert updated.caption == "更新OK"` → `assert updated.summary == "更新OK"`

- [ ] **Step 3: Update extracted_image_test.exs**

Line 16: `caption: "テストキャプション"` → `summary: "テストサマリー"`

- [ ] **Step 4: Update general_archive_test.exs**

Line 20: `:caption,` → `:summary,`

- [ ] **Step 5: Update yaml_cache_test.exs**

Line 19: `%{field: :caption}` → `%{field: :summary}`

- [ ] **Step 6: Update yaml_loader_test.exs**

Line 12: `&(&1.field == :caption)` → `&(&1.field == :summary)`
Line 21: `{"bad_missing_caption.yaml", ~r/caption|missing/}` → `{"bad_missing_summary.yaml", ~r/summary|missing/}`
Line 23: `{"bad_caption_metadata_storage.yaml", ~r/storage: core/}` → `{"bad_summary_metadata_storage.yaml", ~r/storage: core/}`
Line 82: `&(&1.field == :caption)` → `&(&1.field == :summary)`

- [ ] **Step 7: Update reserved_keys_test.exs**

Line 9: `"rejects keys that are statically reserved (e.g. caption)"` → `"rejects keys that are statically reserved (e.g. summary)"`
Line 10: `%{field_key: "caption", ...}` → `%{field_key: "summary", ...}`

- [ ] **Step 8: Update search_test.exs**

Replace all `caption:` with `summary:` in test data:
Line 17: `caption: "第1図 縄文土器出土状況"` → `summary: "第1図 縄文土器出土状況"`
Line 30: `caption: "第2図 弥生時代の銅鉛"` → `summary: "第2図 弥生時代の銅鉛"`
Line 43: `caption: "第3図 下書きの図版"` → `summary: "第3図 下書きの図版"`
Line 275: `caption: "市史写真"` → `summary: "市史写真"`
Line 304: `caption: "館報"` → `summary: "館報"`

- [ ] **Step 9: Update search_live_test.exs**

Line 41: `caption: "テスト土器の出土状況"` → `summary: "テスト土器の出土状況"`
Line 59: `caption: "テスト"` → `summary: "テスト"`

- [ ] **Step 10: Update label_test.exs**

Replace all `caption:` and `"caption"` occurrences:
Lines 28, 46: `caption: "テスト土器第3図"` → `summary: "テスト土器第3図"`
Line 99: `caption: nil` → `summary: nil`
Line 204: `caption: "既存の図版"` → `summary: "既存の図版"`
Line 225: `"caption" => ""` → `"summary" => ""`
Line 244: `caption: "PDF A の図版"` → `summary: "PDF A の図版"`
Line 266: `"caption" => ""` → `"summary" => ""`
Line 300: `"caption" => ""` → `"summary" => ""`
Line 337: `"caption" => ""` → `"summary" => ""`
Line 361: `caption: "既存の図版"` → `summary: "既存の図版"`
Line 382: `"caption" => ""` → `"summary" => ""`
Line 439: `caption: "既存の資料"` → `summary: "既存の資料"`
Line 457: `"caption" => ""` → `"summary" => ""`

- [ ] **Step 11: Update finalize_test.exs**

Line 21: `caption: "テスト土器第3図"` → `summary: "テスト土器第3図"`
Line 74: `%{caption: nil, ...}` → `%{summary: nil, ...}`

- [ ] **Step 12: Update gallery_live_test.exs**

Line 65: `caption: "ギャラリー検索テスト"` → `summary: "ギャラリー検索テスト"`
Line 149: `caption: "テストキャプション"` → `summary: "テストサマリー"`

- [ ] **Step 13: Commit**

```bash
git add test/
git commit -m "feat: rename caption to summary in all test files"
```

---

## Task 11: Reset, Test & Verify

- [ ] **Step 1: Run mix ecto.reset**

Run: `mix ecto.reset`
Expected: Database drops, creates, and all migrations run successfully including the new rename migration.

- [ ] **Step 2: Run mix test**

Run: `mix test`
Expected: All tests pass.

- [ ] **Step 3: Run mix review**

Run: `mix review`
Expected: No compile warnings, credo strict passes, sobelow passes, dialyzer passes.

- [ ] **Step 4: Run grep for remaining caption references**

Run: `grep -r "caption" lib/ priv/ test/ --include="*.ex" --include="*.exs" --include="*.yaml"`
Expected: No output (zero remaining caption references in code). Existing migration files in `priv/repo/migrations/` that predate this change are acceptable.

Run: `grep -r "caption" lib/ priv/profiles/ test/ --include="*.ex" --include="*.exs" --include="*.yaml" --include="*.css" | grep -v "priv/repo/migrations/"`
Expected: No output.

- [ ] **Step 5: Commit any remaining fixes**

If any caption references were found in Step 4, fix them and commit:

```bash
git add -A
git commit -m "fix: remove remaining caption references found by grep"
```

---

## Task 12: Final Verification & Report

- [ ] **Step 1: Run full verification suite again**

```bash
mix ecto.reset && mix test && mix review
```

Expected: All three commands succeed.

- [ ] **Step 2: Generate final report**

List all changed files with one-line reasons:
```bash
git diff --stat HEAD~N  # where N = number of commits in this feature
```

Show the migration file name:
```bash
ls priv/repo/migrations/*caption*summary* 2>/dev/null || ls priv/repo/migrations/*rename* 2>/dev/null
```

Confirm no remaining caption references:
```bash
grep -r "caption" lib/ priv/profiles/ test/ --include="*.ex" --include="*.exs" --include="*.yaml" --include="*.css" | grep -v "priv/repo/migrations/"
```
