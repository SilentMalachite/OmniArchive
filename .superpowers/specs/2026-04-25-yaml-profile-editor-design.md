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
| 保存と適用の分離 | 「下書き保存」（ファイル書き込み）と「適用」（`YamlCache.reload!`）を別ボタンで操作 |
| 環境変数未設定時 | フォーム非表示、設定方法のメッセージのみ表示 |

---

## アーキテクチャ

### アプローチ: タブ型シングル LiveView

1つの LiveView `YamlProfileLive` にすべてのセクションをタブとして収める。セクション間の依存（`validation_rules` / `search_facets` / `duplicate_identity` が `metadata_fields` のフィールド名を参照）を同一 LiveView のメモリ上で管理できるため、一貫性を保ちやすい。

### 新規ファイル

- `lib/omni_archive_web/live/admin/yaml_profile_live.ex`

### 変更ファイル

- `lib/omni_archive_web/router.ex` — `live "/yaml_profile", YamlProfileLive, :index` を admin スコープに追加
- 管理レイアウト — タブナビゲーションに「YAMLプロファイル」リンクを追加
- `mix.exs` — `{:ymlr, "~> 5.0"}` を追加（YAML エンコード用）

---

## LiveView の状態

| assign | 型 | 説明 |
|---|---|---|
| `@active_tab` | atom | 現在表示中のタブ（`:metadata_fields` など） |
| `@yaml_path` | string \| nil | 環境変数 `OMNI_ARCHIVE_PROFILE_YAML` の値 |
| `@profile_state` | `:unconfigured \| :new \| :loaded` | UIの表示モードを制御 |
| `@fields` | list | metadata_fields の編集中リスト |
| `@validation_rules` | map | フィールドキー → バリデーションルールのマップ |
| `@search_facets` | list | search_facets の編集中リスト |
| `@duplicate_identity` | map | duplicate_identity の編集中値 |
| `@ui_texts` | map | ui_texts の編集中値（search / inspector_label） |
| `@has_unsaved_changes` | bool | 未保存変更の有無（適用ボタンの活性制御） |
| `@validation_errors` | map | セクション別バリデーションエラー |

### `@profile_state` の遷移

| 状態 | 条件 | UIの動作 |
|---|---|---|
| `:unconfigured` | 環境変数未設定 | フォーム非表示。設定方法のメッセージを表示 |
| `:new` | 環境変数あり・ファイル未存在 | 全セクション空欄で新規作成モード |
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
- `format` 入力時はリアルタイムで正規表現の構文チェック（`Regex.compile/1`）
- `metadata_fields` に存在しないフィールドのルールは表示しない

### タブ3: `search_facets`

リスト管理UI。

- `field` は `metadata_fields` で定義済みのフィールドのみプルダウンで選択可
- 各エントリに `field` / `param` / `label` を入力

### タブ4: `duplicate_identity`

単一マップのシンプルなフォーム。

- `scope_field` / `label_field` は `metadata_fields` のプルダウン
- `profile_key` / `duplicate_label_error` はテキスト入力

### タブ5: `ui_texts`

2サブセクション（`search` 11項目 / `inspector_label` 8項目）のテキスト入力フォーム。必須キーはすべて `YamlLoader` の `@required_search_keys` / `@required_inspector_keys` に準拠。

---

## データフロー

### 下書き保存（`handle_event("save_draft")`）

```
1. assigns の全セクションを YAML マップに組み立て
2. ymlr でエンコード（YAML 文字列化）
3. YamlLoader.load/1 でバリデーション
   ├─ {:error, reason} → @validation_errors に格納、タブバッジ + インラインエラー表示
   └─ {:ok, _} → File.write(@yaml_path, yaml_string)
4. @has_unsaved_changes = false
5. フラッシュ: "プロファイルを保存しました（まだ適用されていません）"
```

### 適用（`handle_event("activate")`）

```
1. @has_unsaved_changes == false であることを確認
2. YamlCache.reload!()
3. :timer.sleep(50) で GenServer 再起動完了を待つ
4. フラッシュ: "プロファイルを適用しました"
```

---

## エラー処理

| ケース | 対応 |
|---|---|
| `File.write` 失敗（パーミッションエラーなど） | `{:error, reason}` をキャッチしてフラッシュエラー表示 |
| `YamlLoader` バリデーション失敗 | タブバッジに `⚠️` 表示 + フォーム内にインラインエラー |
| `YamlCache.reload!` 中の短時間の ETS 空状態 | 許容（ミリ秒以内で supervisor が再起動） |
| `metadata_fields` 削除によって `validation_rules` / `search_facets` に孤立参照が生じる | 保存時に `YamlLoader` が検知してエラー表示 |

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
| 適用フロー（`YamlCache.reload!` 後の ETS 内容変化を確認） | 同上 |
| `ymlr` エンコード → `YamlLoader` デコードのラウンドトリップ | `test/omni_archive/domain_profiles/yaml_roundtrip_test.exs` |

---

## スコープ外

- 複数 YAML プロファイルの管理（プロファイル切り替えUI）
- YAML プロファイルのバージョン管理・履歴
- プロファイルのエクスポート/インポート
- `ui_texts` への任意キー追加（必須キーのみ対応）
