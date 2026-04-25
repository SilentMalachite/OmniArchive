# YAML プロファイルエディター 設計仕様

**日付:** 2026-04-25  
**対象:** `/admin/yaml_profile` — 管理者が YAML ドメインプロファイルを UI 上で編集・適用できる機能

---

## 背景と目的

OmniArchive は `OMNI_ARCHIVE_PROFILE_YAML` 環境変数で指定した YAML ファイルをドメインプロファイルとして読み込む。現状このファイルはファイルシステム上で直接編集する必要があり、管理者が GUI から変更できない。本機能は `/admin` 画面に YAML プロファイルの構造化フォームエディターを追加し、再起動なしでプロファイルを更新できるようにする。

---

## 決定済み要件

| 項目 | 内容 |
|---|---|
| 保存先 | `OMNI_ARCHIVE_PROFILE_YAML` 環境変数が指すファイルパス（外部ディレクトリ） |
| テンプレート参照 | `priv/profiles/example_profile.yaml`（変更不要、読み取り専用） |
| 編集対象セクション | 全5セクション（metadata_fields / validation_rules / search_facets / duplicate_identity / ui_texts） |
| 保存と適用の分離 | 「下書き保存」（ファイル書き込み）と「適用」（同期的な `YamlCache.reload_from_disk/0`）を別ボタンで操作 |
| 環境変数未設定時 | フォーム非表示、設定方法のメッセージのみ表示 |
| 初回作成 | 環境変数あり・ファイル未存在でもアプリは起動し、テンプレート内容を初期値にした新規作成モードを表示 |

---

## アーキテクチャ

### アプローチ: タブ型シングル LiveView

1つの LiveView `YamlProfileLive` にすべてのセクションをタブとして収める。セクション間の依存（`validation_rules` / `search_facets` / `duplicate_identity` が `metadata_fields` のフィールド名を参照）を同一 LiveView のメモリ上で管理できるため、一貫性を保ちやすい。

### 新規ファイル

- `lib/omni_archive_web/live/admin/yaml_profile_live.ex`

### 変更ファイル

- `lib/omni_archive_web/router.ex` — `live "/yaml_profile", YamlProfileLive, :index` を admin スコープに追加
- 管理レイアウト — タブナビゲーションに「YAMLプロファイル」リンクを追加
- `config/runtime.exs` — `OMNI_ARCHIVE_PROFILE_YAML` が未存在ファイルを指しても起動時に raise しない
- `lib/omni_archive/domain_profiles/yaml_loader.ex` — `load_string/1` と UI 必須キー参照関数を追加
- `lib/omni_archive/domain_profiles/yaml_cache.ex` — テンプレート fallback と同期的な安全 reload を追加
- `mix.exs` — `{:ymlr, "~> 5.0"}` を追加（YAML エンコード用）

---

## 起動時設定と初回作成

現状の `config/runtime.exs` は `OMNI_ARCHIVE_PROFILE_YAML` が未存在ファイルを指すと起動時に raise する。このままでは `:new` モードの LiveView に到達できないため、本機能では次の挙動に変更する。

- `OMNI_ARCHIVE_PROFILE_YAML` が未設定の場合は従来どおり YAML profile を有効化しない。
- `OMNI_ARCHIVE_PROFILE_YAML` が設定されている場合は、ファイル存在有無にかかわらず `:domain_profile_yaml_path` を設定し、active profile を `OmniArchive.DomainProfiles.Yaml` にする。
- `YamlCache.init/1` は対象 YAML が存在する場合はそれを読み込む。存在しない場合は `priv/profiles/example_profile.yaml` を読み込んで一時的な in-memory profile として使う。
- LiveView の `:new` 判定は `File.exists?(@yaml_path) == false` で行う。フォーム初期値はテンプレートから読み込むが、テンプレートファイル自体は絶対に書き換えない。
- 対象 YAML が未存在のまま「適用」を押した場合はエラーにする。最初に下書き保存で対象パスへファイルを作成する。

## LiveView の状態

| assign | 型 | 説明 |
|---|---|---|
| `@active_tab` | atom | 現在表示中のタブ（`:metadata_fields` など） |
| `@yaml_path` | string \| nil | 環境変数 `OMNI_ARCHIVE_PROFILE_YAML` の値 |
| `@profile_state` | `:unconfigured \| :new \| :loaded` | UIの表示モードを制御 |
| `@fields` | list | metadata_fields の編集中リスト |
| `@validation_rules` | map | フィールドキー → バリデーションルールのマップ（`format` は生文字列で保持、コンパイル済み Regex は持たない） |
| `@search_facets` | list | search_facets の編集中リスト |
| `@duplicate_identity` | map | duplicate_identity の編集中値 |
| `@ui_texts` | map | ui_texts の編集中値（search / inspector_label） |
| `@has_unsaved_changes` | bool | フォームに未保存の変更があるか（true = ファイルと不一致） |
| `@draft_saved` | bool | このセッションでファイルを保存したか（true = 適用ボタン有効の前提条件） |
| `@validation_errors` | map | セクション別バリデーションエラー |

### `@profile_state` の遷移

| 状態 | 条件 | UIの動作 |
|---|---|---|
| `:unconfigured` | 環境変数未設定 | フォーム非表示。設定方法のメッセージを表示 |
| `:new` | 環境変数あり・ファイル未存在 | `priv/profiles/example_profile.yaml` の内容を初期値にした新規作成モード |
| `:loaded` | 環境変数あり・ファイル存在 | 既存内容をフォームに読み込んで表示 |

---

## 各タブの UI

### タブ1: `metadata_fields`

`CustomFieldsLive` に類似したリスト管理UI。

- `summary` / `label` は `storage: core` 固定 — 削除不可、storage 変更不可
- その他フィールドは削除・並べ替え可
- インライン編集フォーム（行クリックで展開）
- フィールドキーの形式は `YamlLoader` 準拠（`^[a-z][a-z0-9_]{0,49}$`）

### タブ2: `validation_rules`

`metadata_fields` で定義済みのフィールドをプルダウンで選択し、ルールを設定。

- 対応ルール: `max_length` / `max_length_error` / `format` / `format_error` / `required_terms` / `required_terms_error`
- `format` は `@validation_rules` assigns に**生の文字列（raw pattern）**として保持する。`YamlLoader` はロード時にコンパイル済み `Regex` 構造体を返すが、`ymlr` はそれをシリアライズできないため、フォーム側では元の文字列を使う。`format` 入力時はリアルタイムで `Regex.compile/1` を使い構文チェックのみ行う。
- `metadata_fields` に存在しないフィールドのルールは孤立参照として表示し、保存時にエラーにする。フィールド削除時は関連ルール・ファセットも削除する確認 UI を出す。

### タブ3: `search_facets`

リスト管理UI。

- `field` は `metadata_fields` で定義済みのフィールドのみプルダウンで選択可
- 各エントリに `field` / `param` / `label` を入力

### タブ4: `duplicate_identity`

単一マップのシンプルなフォーム。

- `scope_field` / `label_field` は `metadata_fields` のプルダウン
- `profile_key` は新規作成時のみ編集可。既存 YAML では読み取り専用にする（既存 fingerprint と runtime custom fields が `profile_key` に依存するため）
- `duplicate_label_error` はテキスト入力

### タブ5: `ui_texts`

2サブセクション（`search` 11項目 / `inspector_label` 6項目）のテキスト入力フォーム。必須キーは `YamlLoader.required_ui_text_keys(:search)` / `YamlLoader.required_ui_text_keys(:inspector_label)` で参照し、LiveView 側で private module attribute を重複定義しない。

---

## YAML 読み書き方針

- フォーム初期値は `YamlElixir.read_from_file/1` で取得した raw map から作る。`YamlLoader.load/1` の戻り値は atom key 化・Regex コンパイル済みなので、編集状態の復元には使わない。
- `:new` モードでは `priv/profiles/example_profile.yaml` の raw map を読み込み、`@yaml_path` への保存候補として表示する。
- 保存時は string key の map を組み立て、`Ymlr.document!/2` で YAML 文字列化する。
- バリデーション用に `YamlLoader.load_string/1` を追加する。`load/1` と `load_string/1` は共通の `parse_raw/1` に委譲し、検証ロジックを重複させない。
- `format` は保存前まで raw string のまま保持する。`load_string/1` が成功した時点で Regex として妥当と判断する。

---

## データフロー

### 下書き保存（`handle_event("save_draft")`）

```
1. assigns の全セクションを YAML マップに組み立て
2. ymlr でエンコード（YAML 文字列化）
3. YamlLoader.load_string/1 でバリデーション
   ├─ {:error, reason} → @validation_errors に格納、タブバッジ + インラインエラー表示
   └─ {:ok, _} → 同一ディレクトリの一時ファイルへ書き込み後、File.rename/2 で @yaml_path に atomic 置換
4. File.write / File.rename 失敗時はフラッシュエラー表示
5. @has_unsaved_changes = false、@draft_saved = true
6. フラッシュ: "プロファイルを保存しました（まだ適用されていません）"
```

### 適用（`handle_event("activate")`）

適用ボタンは `@draft_saved == true and @has_unsaved_changes == false` のときのみ有効。

```
1. YamlCache.reload_from_disk()
   ├─ GenServer.call で同期実行
   ├─ @yaml_path を YamlLoader.load/1 で読み込み・検証
   ├─ 成功時のみ ETS の profile tuple を差し替える
   └─ 失敗時は既存 cache を維持して {:error, reason} を返す
2. {:error, reason} → フラッシュエラー表示（既存 profile は継続）
3. {:ok, _profile} → @draft_saved = false
4. フラッシュ: "プロファイルを適用しました"
```

`YamlCache` は個別キーを複数行で ETS に保存するのではなく、`{:profile, profile_map}` の単一 tuple を保存する。これにより reload 中の空状態や、metadata_fields だけ新旧が混ざる中間状態を避ける。

---

## エラー処理

| ケース | 対応 |
|---|---|
| `File.write` 失敗（パーミッションエラーなど） | `{:error, reason}` をキャッチしてフラッシュエラー表示 |
| `YamlLoader` バリデーション失敗 | タブバッジに `⚠️` 表示 + フォーム内にインラインエラー |
| `YamlCache.reload_from_disk/0` 失敗 | 既存 cache を維持し、適用失敗のフラッシュを表示 |
| reload 中の ETS 空状態 | 許容しない。単一 profile tuple の差し替えで中間状態を作らない |
| `metadata_fields` 削除によって `validation_rules` / `search_facets` に孤立参照が生じる | UI で孤立参照として表示し、保存時に `YamlLoader` が検知してエラー表示 |
| 対象ファイルが外部で更新済み | mount 時に mtime または content hash を保存し、下書き保存時に変化していれば上書きを止める |

---

## 依存関係の追加

`YamlElixir` はデコード専用のため、YAML エンコード（Elixir map → YAML 文字列）に `ymlr` を追加する。`CLAUDE.md` の「No new dependencies unless required」ポリシーに対して、YAML 書き込み機能の実現には必須の依存であるため許容する。

```elixir
# mix.exs
{:ymlr, "~> 5.0"}
```

---

## テスト方針

| テスト | ファイル |
|---|---|
| `mount` の3状態（unconfigured / new / loaded） | `test/omni_archive_web/live/admin/yaml_profile_live_test.exs` |
| 下書き保存フロー（正常系・バリデーションエラー系） | 同上（実ファイルを一時ディレクトリに作成して検証） |
| 適用フロー（`YamlCache.reload_from_disk/0` 後に ETS の内容が更新されること + `@draft_saved` が false になること） | 同上 |
| `load_string/1` と `load/1` が同じ検証結果を返すこと | `test/omni_archive/domain_profiles/yaml_loader_test.exs` |
| `YamlCache.reload_from_disk/0` が invalid YAML で既存 cache を維持すること | `test/omni_archive/domain_profiles/yaml_cache_test.exs` |
| `ymlr` エンコード → `YamlLoader.load_string/1` デコードのラウンドトリップ | `test/omni_archive/domain_profiles/yaml_roundtrip_test.exs` |
| 既存 YAML の `format` が raw string としてフォームに復元されること | `test/omni_archive_web/live/admin/yaml_profile_live_test.exs` |

---

## スコープ外

- 複数 YAML プロファイルの管理（プロファイル切り替えUI）
- YAML プロファイルのバージョン管理・履歴
- プロファイルのエクスポート/インポート
- `ui_texts` への任意キー追加（必須キーのみ対応）
