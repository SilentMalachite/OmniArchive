# Default Domain Profile → `GeneralArchive` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** デフォルトドメインプロファイルを `OmniArchive.DomainProfiles.Archaeology` から `OmniArchive.DomainProfiles.GeneralArchive` に切り替える。`Archaeology` プロファイル本体はオプトインで使い続けられる。

**Architecture:** `Application.get_env(:omni_archive, :domain_profile, ...)` のフォールバック値とコンパイル時の `Application.compile_env(...)` のデフォルト値を 3 箇所差し替える。`config/test.exs` は上書きしない方針なので、Archaeology を前提にしているテストには `put_domain_profile(Archaeology)` を明示的に追加して挙動カバレッジを維持する。

**Tech Stack:** Elixir / Phoenix / ExUnit / `OmniArchive.DomainProfileTestHelper`（`test/support/domain_profile_test_helper.ex`）。

**Spec:** `docs/superpowers/specs/2026-04-26-default-profile-general-archive-design.md`

---

## File Structure

| File | Role | Change |
|---|---|---|
| `config/config.exs` | コンパイル時設定 | `domain_profile` を `GeneralArchive` に |
| `lib/omni_archive/domain_profiles.ex` | プロファイル accessor | `@default_profile` を `GeneralArchive` に |
| `lib/omni_archive/custom_metadata_fields/custom_metadata_field.ex` | カスタムフィールドの reserved key 計算 | フォールバックを `GeneralArchive` に |
| `test/omni_archive/domain_profiles_test.exs` | ドメインプロファイル全般テスト | デフォルト = GeneralArchive を検証する内容に書き換え |
| `test/omni_archive/domain_profiles/general_archive_test.exs` | GeneralArchive テスト | 「Archaeology デフォルト維持」テストを反転 + Archaeology オプトインテスト追加 |
| `test/omni_archive/duplicate_lookup_test.exs` | 重複検出テスト（Archaeology 前提） | Archaeology ケースに `put_domain_profile(Archaeology)` 追加 |
| `test/omni_archive/duplicate_identity_test.exs` | fingerprint テスト（Archaeology 前提） | 同上 |
| `test/omni_archive/ingestion/extracted_image_dedupe_test.exs` | dedupe テスト（Archaeology 前提） | 同上 |
| `README.md` | プロジェクト README | 「(デフォルト)」マーカーを GeneralArchive 側に移動、変更ノート追記 |
| `CLAUDE.md` | エージェント向け説明 | 設定例を `GeneralArchive` に更新 |

**変更しないファイル（YAGNI）:**
- `lib/omni_archive/domain_profiles/archaeology.ex` — オプトインで使えるよう温存
- `config/test.exs` — テスト環境はデフォルトを継承する方針
- `priv/repo/seeds.exs` — profile 非依存の `:map` メタデータのみ
- マイグレーションは追加しない（DB スキーマ無変更）

---

## Task 1: Archaeology 前提の単体テストにオプトイン宣言を追加（無破壊）

**Why first:** 後で default を flip した時に「想定外で落ちる」テストを先に守る。この時点では default はまだ Archaeology なのでテスト挙動は変わらず、green のまま commit できる。

**Files:**
- Modify: `test/omni_archive/duplicate_lookup_test.exs`
- Modify: `test/omni_archive/duplicate_identity_test.exs`
- Modify: `test/omni_archive/ingestion/extracted_image_dedupe_test.exs`

- [ ] **Step 1: `duplicate_lookup_test.exs` の Archaeology テストにオプトイン追加**

`test/omni_archive/duplicate_lookup_test.exs` の `test "Archaeology で duplicate fingerprint を使って重複を見つける" do` ブロックの先頭（`existing =` の直前）に以下を挿入:

```elixir
      put_domain_profile(OmniArchive.DomainProfiles.Archaeology)
```

- [ ] **Step 2: `duplicate_identity_test.exs` の Archaeology fingerprint テストにオプトイン追加**

`test/omni_archive/duplicate_identity_test.exs` の `test "Archaeology で profile key + site + label から fingerprint を作る" do` ブロックの先頭（`image =` の直前）に以下を挿入:

```elixir
      put_domain_profile(OmniArchive.DomainProfiles.Archaeology)
```

> 注: 同ファイルの `test "空文字や nil を含む場合は fingerprint を作らない"` は `fingerprint_from_values("archaeology", ...)` のように profile_key を文字列リテラルで渡しているため active profile に非依存。**変更しない**。

- [ ] **Step 3: `extracted_image_dedupe_test.exs` の Archaeology dedupe テストにオプトイン追加**

`test/omni_archive/ingestion/extracted_image_dedupe_test.exs` の `test "Archaeology で dedupe_fingerprint を自動計算する" do` ブロックの先頭（`pdf_source =` の直前）に以下を挿入:

```elixir
      put_domain_profile(OmniArchive.DomainProfiles.Archaeology)
```

- [ ] **Step 4: 変更したテストを実行して green を確認**

Run:
```bash
mix test test/omni_archive/duplicate_lookup_test.exs test/omni_archive/duplicate_identity_test.exs test/omni_archive/ingestion/extracted_image_dedupe_test.exs
```
Expected: 全テスト PASS（default はまだ Archaeology なので挙動は変わらない）。

- [ ] **Step 5: Commit**

```bash
git add test/omni_archive/duplicate_lookup_test.exs test/omni_archive/duplicate_identity_test.exs test/omni_archive/ingestion/extracted_image_dedupe_test.exs
git commit -m "test: opt-in to Archaeology profile in fingerprint/dedupe tests

Prepare for the upcoming default-profile switch by making Archaeology-
specific tests explicitly select the Archaeology profile, so they keep
passing once the default flips to GeneralArchive."
```

---

## Task 2: デフォルト = GeneralArchive を期待するテスト群に書き換え（RED 状態を作る）

**Why:** TDD の RED フェーズ。デフォルト変更後の期待挙動を先にコードで宣言し、現状（Archaeology デフォルト）では fail することを確認する。

**Files:**
- Modify: `test/omni_archive/domain_profiles_test.exs`（完全書き換え）
- Modify: `test/omni_archive/domain_profiles/general_archive_test.exs:47-61`

- [ ] **Step 1: `domain_profiles_test.exs` を完全書き換え**

`test/omni_archive/domain_profiles_test.exs` の中身を以下で **置き換え**:

```elixir
defmodule OmniArchive.DomainProfilesTest do
  use ExUnit.Case, async: true

  alias OmniArchive.DomainProfiles
  alias OmniArchive.DomainProfiles.GeneralArchive

  test "active profile defaults to GeneralArchive" do
    assert DomainProfiles.current() == GeneralArchive
  end

  test "search facet definitions match GeneralArchive" do
    assert DomainProfiles.search_facets() == [
             %{field: :collection, param: "collection", label: "🗂️ コレクション"},
             %{field: :item_type, param: "item_type", label: "📁 資料種別"},
             %{field: :date_note, param: "date_note", label: "📅 年代メモ"}
           ]
  end

  test "duplicate identity defaults to GeneralArchive" do
    assert DomainProfiles.profile_key() == "general_archive"
    assert DomainProfiles.duplicate_scope_field() == :collection
  end
end
```

- [ ] **Step 2: `general_archive_test.exs` の「Archaeology デフォルト維持」テストを反転 + Archaeology オプトインテスト追加**

`test/omni_archive/domain_profiles/general_archive_test.exs` の `test "Archaeology デフォルトは維持される" do ... end` ブロック（47–61 行目周辺）を以下で **置き換え**:

```elixir
  test "デフォルトは GeneralArchive" do
    restore = Application.get_env(:omni_archive, :domain_profile)
    Application.delete_env(:omni_archive, :domain_profile)

    try do
      assert DomainProfiles.current() == GeneralArchive
    after
      if restore do
        Application.put_env(:omni_archive, :domain_profile, restore)
      else
        Application.delete_env(:omni_archive, :domain_profile)
      end
    end
  end

  test "put_domain_profile(Archaeology) で Archaeology にオプトインできる" do
    put_domain_profile(Archaeology)
    assert DomainProfiles.current() == Archaeology
    assert DomainProfiles.profile_key() == "archaeology"
    assert DomainProfiles.duplicate_scope_field() == :site
  end
```

- [ ] **Step 3: 変更したテストを実行し、RED であることを確認**

Run:
```bash
mix test test/omni_archive/domain_profiles_test.exs test/omni_archive/domain_profiles/general_archive_test.exs
```
Expected: **FAIL**（少なくとも以下が失敗するはず）
- `domain_profiles_test.exs` の 3 テスト全て（`current() == GeneralArchive` を期待しているが現状は `Archaeology`）
- `general_archive_test.exs` の "デフォルトは GeneralArchive"（同上）
- "put_domain_profile(Archaeology) で..." は `put_domain_profile` で明示的に上書きするので PASS する想定

> Step 3 の段階ではまだ commit しない。Task 3 の実装と同じ commit にまとめる。

---

## Task 3: デフォルトを `GeneralArchive` に切り替え（GREEN）

**Why:** 仕様の本体。3 箇所のフォールバック / コンパイル時デフォルトを `GeneralArchive` に flip。Task 2 で書いたテストが GREEN になることを確認する。

**Files:**
- Modify: `config/config.exs:24`
- Modify: `lib/omni_archive/domain_profiles.ex:9, 11`
- Modify: `lib/omni_archive/custom_metadata_fields/custom_metadata_field.ex:75`

- [ ] **Step 1: `config/config.exs` のデフォルトを変更**

`config/config.exs:23-26` を以下で置き換え:

```elixir
config :omni_archive,
  domain_profile: OmniArchive.DomainProfiles.GeneralArchive,
  ecto_repos: [OmniArchive.Repo],
  generators: [timestamp_type: :utc_datetime]
```

- [ ] **Step 2: `lib/omni_archive/domain_profiles.ex` の alias と `@default_profile` を変更**

`lib/omni_archive/domain_profiles.ex:7-11`（`alias` から `@default_profile` まで）を以下で置き換え:

```elixir
  alias OmniArchive.CustomMetadataFields
  alias OmniArchive.CustomMetadataFields.Cache
  alias OmniArchive.DomainProfiles.GeneralArchive

  @default_profile GeneralArchive
```

> `@compile_time_default_profile` の定義（12–16 行目）には触らない。`@default_profile` のみ参照しているので自動的に追従する。

- [ ] **Step 3: `lib/omni_archive/custom_metadata_fields/custom_metadata_field.ex` のフォールバックを変更**

`lib/omni_archive/custom_metadata_fields/custom_metadata_field.ex:71-76`（`Application.get_env(...)` ブロック）を以下で置き換え:

```elixir
    profile =
      Application.get_env(
        :omni_archive,
        :domain_profile,
        OmniArchive.DomainProfiles.GeneralArchive
      )
```

- [ ] **Step 4: フルテスト実行で GREEN 確認**

Run:
```bash
mix test
```
Expected: **全テスト PASS**。Task 2 で RED だったテストが GREEN になっているはず。Task 1 で守った Archaeology 前提テストも green を維持。

- [ ] **Step 5: Commit**

```bash
git add config/config.exs lib/omni_archive/domain_profiles.ex lib/omni_archive/custom_metadata_fields/custom_metadata_field.ex test/omni_archive/domain_profiles_test.exs test/omni_archive/domain_profiles/general_archive_test.exs
git commit -m "feat: switch default domain profile to GeneralArchive

Switch the built-in default profile from Archaeology to GeneralArchive.
Archaeology remains available as an opt-in profile via:

    config :omni_archive, domain_profile: OmniArchive.DomainProfiles.Archaeology

Tests that exercise Archaeology-specific behavior now opt in explicitly
via put_domain_profile/1; default-asserting tests now expect
GeneralArchive."
```

---

## Task 4: ドキュメント更新

**Why:** README と CLAUDE.md に古いデフォルト記述が残ると、新規開発者 / エージェントの参照情報が誤りになる。

**Files:**
- Modify: `README.md:88-92`
- Modify: `CLAUDE.md:60`

- [ ] **Step 1: `README.md` のプロファイル一覧を更新**

`README.md:88-92` 周辺の以下のブロック:

```markdown
利用可能な profile:
- `OmniArchive.DomainProfiles.Archaeology` (デフォルト)
- `OmniArchive.DomainProfiles.GeneralArchive`
- **YAML 定義プロファイル** (v0.2.23 以降): `OMNI_ARCHIVE_PROFILE_YAML` 環境変数で YAML ファイルを指定
```

を以下で置き換え:

```markdown
利用可能な profile:
- `OmniArchive.DomainProfiles.GeneralArchive` (デフォルト)
- `OmniArchive.DomainProfiles.Archaeology`
- **YAML 定義プロファイル** (v0.2.23 以降): `OMNI_ARCHIVE_PROFILE_YAML` 環境変数で YAML ファイルを指定

> デフォルト profile は汎用アーカイブ向けの `GeneralArchive` です。考古学向け `Archaeology` を使う場合は、`config/config.exs` に明示的に `config :omni_archive, domain_profile: OmniArchive.DomainProfiles.Archaeology` を追加してください。
```

- [ ] **Step 2: `CLAUDE.md` の設定例を更新**

`CLAUDE.md:60` の以下の行:

```elixir
config :omni_archive, domain_profile: OmniArchive.DomainProfiles.Archaeology
```

を以下で置き換え:

```elixir
config :omni_archive, domain_profile: OmniArchive.DomainProfiles.GeneralArchive
```

- [ ] **Step 3: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: update default domain profile references to GeneralArchive"
```

---

## Task 5: 検証ゲート `mix review` を通す

**Why:** ユーザー指定の Validation Gate B。compile --warnings-as-errors / format / test に加え credo --strict / sobelow / dialyzer まで通して退行がないことを保証する。

**Files:** （なし — 検証のみ。問題があれば該当ファイルを修正）

- [ ] **Step 1: `mix review` 実行**

Run:
```bash
mix review
```
Expected: **全フェーズ PASS**。具体的には db version / `compile --warnings-as-errors` / `credo --strict` / `sobelow` / `dialyzer`。

- [ ] **Step 2: 指摘があれば fix → 再実行**

`mix review` が指摘を出した場合:
- `credo` warning → 該当ファイルを修正してフォーマット
- `dialyzer` 新規 warning → 型仕様を修正（型シグネチャは変えていないので新規 warning は出にくいはずだが、出たら原因を特定）
- `sobelow` 新規 finding → セキュリティ観点で対応

修正したら commit を分けて積み、再度 `mix review` を実行。green まで繰り返す。

```bash
git add <fixed-files>
git commit -m "fix: address mix review findings"
mix review
```

- [ ] **Step 3: 完了確認**

`mix review` が全 phase green であることを確認したら、本プランの実装は完了。`git log --oneline` で次の commit 列が並んでいることを確認:

```
docs: update default domain profile references to GeneralArchive
feat: switch default domain profile to GeneralArchive
test: opt-in to Archaeology profile in fingerprint/dedupe tests
docs(spec): default domain profile → GeneralArchive design
```

---

## Self-Review Checklist (for the executor)

実装完了後、以下を最終確認:

- [ ] `git grep "DomainProfiles.Archaeology"` の結果が想定範囲内（`archaeology.ex` 自体、Archaeology テストファイル、トラブルシューティング目的の参照のみ）
- [ ] `mix test` フルスイート green
- [ ] `mix review` green（dialyzer 含む）
- [ ] README に「デフォルト変更」のノートが追加されている
- [ ] `Archaeology` モジュールは無変更（`git log --follow lib/omni_archive/domain_profiles/archaeology.ex` で確認）
