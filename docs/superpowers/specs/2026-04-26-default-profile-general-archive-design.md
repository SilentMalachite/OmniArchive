# Design: Default Domain Profile → `GeneralArchive`

## Background

OmniArchive はマルチドメイン対応を意図して設計されているが、現状の組み込みデフォルトは `OmniArchive.DomainProfiles.Archaeology`（考古学向け：site / period / artifact_type など）になっている。これは初期開発の経緯による特化であり、汎用アーカイブ用途のユーザーにとって最初に目にする UI / 用語が分野特有すぎる。

このスペックではデフォルトを `OmniArchive.DomainProfiles.GeneralArchive`（summary / label / collection / item_type / date_note）に切り替える。`Archaeology` プロファイル自体は引き続きオプトインで利用可能とする。

**Precondition:** DB マイグレーション不要（`PdfSource.metadata` は profile 非依存の `:map`）。

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| デフォルト profile | `GeneralArchive` | 汎用用途を前提に。Archaeology は明示オプトイン |
| `Archaeology` モジュール | 残す（無変更） | オプトインで使い続けられるように |
| `config/test.exs` への上書き | しない | 本番デフォルトとテストデフォルトを揃える方針 (A) |
| Archaeology 前提テスト | 各テスト先頭に `put_domain_profile(Archaeology)` を追加 | 各 profile の挙動カバレッジを失わない |
| `domain_profiles_test.exs` のリライト範囲 | 完全書き換え | デフォルト = GeneralArchive を検証する内容に |
| 検証ゲート | `mix review`（dialyzer 含む） | ユーザー指定の Gate B |
| 既存 DB データ | 触らない | `metadata` は profile 非依存 |
| 既存ユーザーへの周知 | README に一行追記のみ | アナウンス機構は YAGNI |

## Scope

### 1. Code (3 files)

#### `config/config.exs:24`
```elixir
# before
config :omni_archive,
  domain_profile: OmniArchive.DomainProfiles.Archaeology,
  ecto_repos: [OmniArchive.Repo],
  generators: [timestamp_type: :utc_datetime]

# after
config :omni_archive,
  domain_profile: OmniArchive.DomainProfiles.GeneralArchive,
  ecto_repos: [OmniArchive.Repo],
  generators: [timestamp_type: :utc_datetime]
```

#### `lib/omni_archive/domain_profiles.ex:9, 11`
```elixir
# before
alias OmniArchive.DomainProfiles.Archaeology
@default_profile Archaeology

# after
alias OmniArchive.DomainProfiles.GeneralArchive
@default_profile GeneralArchive
```

#### `lib/omni_archive/custom_metadata_fields/custom_metadata_field.ex:75`
```elixir
# before
profile =
  Application.get_env(
    :omni_archive,
    :domain_profile,
    OmniArchive.DomainProfiles.Archaeology
  )

# after
profile =
  Application.get_env(
    :omni_archive,
    :domain_profile,
    OmniArchive.DomainProfiles.GeneralArchive
  )
```

### 2. Tests (5 files)

#### `test/omni_archive/domain_profiles_test.exs` — 完全書き換え

新内容（要約）:
- `DomainProfiles.current() == GeneralArchive` を検証
- `search_facets()` が `[:collection, :item_type, :date_note]` を返すことを検証
- `profile_key() == "general_archive"` / `duplicate_scope_field() == :collection` を検証
- 既存の Archaeology アサーションは削除（`general_archive_test.exs` 側の Archaeology オプトインテストでカバー）

#### `test/omni_archive/domain_profiles/general_archive_test.exs:47-61` — テスト反転

```elixir
# before
test "Archaeology デフォルトは維持される" do
  restore = Application.get_env(:omni_archive, :domain_profile)
  Application.delete_env(:omni_archive, :domain_profile)

  try do
    assert DomainProfiles.current() == Archaeology
  after
    if restore do
      Application.put_env(:omni_archive, :domain_profile, restore)
    else
      Application.delete_env(:omni_archive, :domain_profile)
    end
  end
end

# after
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

test "put_domain_profile(Archaeology) でオプトイン可能" do
  put_domain_profile(Archaeology)
  assert DomainProfiles.current() == Archaeology
  assert DomainProfiles.profile_key() == "archaeology"
end
```

#### `test/omni_archive/duplicate_lookup_test.exs:9` — Archaeology オプトイン化

```elixir
test "Archaeology で duplicate fingerprint を使って重複を見つける" do
  put_domain_profile(OmniArchive.DomainProfiles.Archaeology)
  # ...既存のアサーションはそのまま
end
```

#### `test/omni_archive/duplicate_identity_test.exs:9` — Archaeology オプトイン化

```elixir
test "Archaeology で profile key + site + label から fingerprint を作る" do
  put_domain_profile(OmniArchive.DomainProfiles.Archaeology)
  # ...既存のアサーションはそのまま
end
```

「空文字や nil を含む場合は fingerprint を作らない」（同ファイル内）は `fingerprint_from_values("archaeology", ...)` のように profile_key を文字列リテラルで渡しており active profile に依存しないため、`put_domain_profile` 追加は **不要**（無変更）。

「GeneralArchive で metadata-only field から fingerprint を作る」も既に `put_domain_profile(GeneralArchive)` を呼んでいるため無変更。

#### `test/omni_archive/ingestion/extracted_image_dedupe_test.exs:9` — Archaeology オプトイン化

```elixir
test "Archaeology で dedupe_fingerprint を自動計算する" do
  put_domain_profile(OmniArchive.DomainProfiles.Archaeology)
  # ...
end
```

### 3. Docs (2 files)

#### `README.md:90`
```markdown
# before
- `OmniArchive.DomainProfiles.Archaeology` (デフォルト)
- `OmniArchive.DomainProfiles.GeneralArchive`

# after
- `OmniArchive.DomainProfiles.GeneralArchive` (デフォルト)
- `OmniArchive.DomainProfiles.Archaeology`
```

加えて「デフォルト profile が Archaeology から GeneralArchive に変わった」一行ノートを近傍に追記する。

#### `CLAUDE.md:60`
```elixir
# before
config :omni_archive, domain_profile: OmniArchive.DomainProfiles.Archaeology

# after
config :omni_archive, domain_profile: OmniArchive.DomainProfiles.GeneralArchive
```

## Validation Gate

ユーザー指定の **Gate B**:

```bash
mix review
```

これは `mix precommit`（compile --warnings-as-errors / format / test）に加えて credo --strict / sobelow / dialyzer まで通す。`AGENTS.md` に倣い、グリーンを確認するまで完了宣言しない。

## Out of Scope

- DB マイグレーション（`metadata` は profile 非依存）
- 既存ユーザー向けのアナウンス機構（README 一行追記のみ）
- `Archaeology` モジュール本体の変更
- YAML profile / `runtime.exs` のロジック（YAML 環境変数指定時の動作は変更しない）
- 既存の seed データ（`priv/repo/seeds.exs`）の確認 — 必要であれば実装中に判断

## Risks

| Risk | Mitigation |
|---|---|
| Archaeology 前提のテスト見落とし | `mix review` で全テスト実行して網羅 |
| dialyzer の type spec 退行 | 型シグネチャは変えていないので低リスク。万一出たら fix |
| 既存ユーザーが暗黙に Archaeology に依存している | README の周知＋`config :omni_archive, domain_profile: ...Archaeology` 一行追加で復元可能 |
