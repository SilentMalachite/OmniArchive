# YAML ドメインプロファイル

## 概要

OmniArchive は従来、`Archaeology` と `GeneralArchive` という 2 つの組み込みドメインプロファイルをコンパイル時に定義していました。バージョン 0.2.23 以降、YAML ファイルでドメインプロファイルを定義できるようになり、アプリケーション起動時に柔軟にプロファイルを切り替えることが可能になりました。

既存の `Archaeology` / `GeneralArchive` は引き続き利用可能です。環境変数を設定しない場合は従来通り `Archaeology` がデフォルトとして動作します。

## 有効化方法

YAML ベースのドメインプロファイルを使用するには、環境変数 `OMNI_ARCHIVE_PROFILE_YAML` を設定してアプリケーションを起動します：

```bash
OMNI_ARCHIVE_PROFILE_YAML=$PWD/priv/profiles/example_profile.yaml mix phx.server
```

または、絶対パスで指定することもできます：

```bash
OMNI_ARCHIVE_PROFILE_YAML=/absolute/path/to/profiles/my_profile.yaml mix phx.server
```

環境変数が設定されていない場合は、従来通り `Archaeology` プロファイルが有効になります。

## 推奨配置場所

YAML プロファイルは `priv/profiles/` ディレクトリ以下に配置することを推奨します。ただし、絶対パスであればどこでも配置可能です。

```
OmniArchive/
└── priv/
    └── profiles/
        ├── example_profile.yaml      # サンプル
        ├── museum_profile.yaml       # カスタム例
        └── archive_profile.yaml      # カスタム例
```

## YAML 構造

### メタデータフィールド (`metadata_fields`)

配列で、各要素は以下のキーを持ちます：

| キー | 型 | 必須 | 説明 |
|:---|:---|:---:|:---|
| `field` | string | ✅ | フィールド識別子。小文字・数字・アンダースコアのみ、先頭は小文字。`caption` / `label` は必須で指定する必要があります。 |
| `label` | string | ✅ | UI に表示するラベル。日本語対応。 |
| `storage` | string | ✅ | `core` または `metadata`。`core` に指定できるのは `caption` / `label` のみです。 |
| `placeholder` | string | | 入力フィールドのプレースホルダーテキスト。 |

**重要な制約**：
- `caption` フィールドは必ず定義し、`storage: core` で指定すること
- `label` フィールドは必ず定義し、`storage: core` で指定すること
- `storage: core` に指定できるのは `caption` / `label` のみ

例：

```yaml
metadata_fields:
  - field: caption
    storage: core
    label: "キャプション"
    placeholder: "例: 表紙の写真"

  - field: label
    storage: core
    label: "ラベル"
    placeholder: "例: photo-001"

  - field: collection
    storage: metadata
    label: "コレクション"
    placeholder: "例: 広報写真アーカイブ"
```

### バリデーション規則 (`validation_rules`)

フィールド単位の入力検証を定義します。キーはフィールド名 (atom に変換)、値は検証ルール定義のマップ。

| キー | 型 | 説明 |
|:---|:---|:---|
| `max_length` | number | 最大文字数制限 |
| `max_length_error` | string | 最大文字数超過時のエラーメッセージ |
| `format` | string | 正規表現パターン（文字列）。自動的に Regex にコンパイルされます |
| `format_error` | string | 形式不一致時のエラーメッセージ |
| `required_terms` | array of string | 含まれるべき必須用語リスト |
| `required_terms_error` | string | 必須用語不在時のエラーメッセージ |

例：

```yaml
validation_rules:
  caption:
    max_length: 1000
    max_length_error: "1000文字以内で入力してください"

  label:
    format: "^[a-z0-9]+(?:-[a-z0-9]+)*$"
    format_error: "半角小文字・数字・ハイフンのみで入力してください"

  collection:
    max_length: 120
    max_length_error: "120文字以内で入力してください"
```

### 検索ファセット (`search_facets`)

Gallery や Lab Search で利用可能なフィルタリング用メタデータ項目を定義します。

| キー | 型 | 説明 |
|:---|:---|:---|
| `field` | string | フィルタリング対象のフィールド名（metadata_fields 内で定義済みであること） |
| `param` | string | URL クエリパラメータ名 |
| `label` | string | UI に表示するファセット名 |

例：

```yaml
search_facets:
  - field: collection
    param: collection
    label: "コレクション"

  - field: era
    param: era
    label: "年代"
```

### UI テキスト (`ui_texts`)

検索・検査画面で表示されるテキストメッセージを定義します。

#### `ui_texts.search` （必須キー）

| キー | 説明 |
|:---|:---|
| `page_title` | ページタイトル |
| `heading` | 見出し |
| `description` | ページ説明文 |
| `placeholder` | 検索入力のプレースホルダー |
| `empty_filtered` | フィルター適用後に結果なしの場合のメッセージ |
| `empty_filtered_hint` | フィルター適用時の無結果ヒント |
| `empty_initial` | 初期状態（データなし）のメッセージ |
| `empty_initial_hint` | 初期状態のヒント |
| `result_none` | 結果なしの表示 |
| `result_suffix` | 検索結果の件数表示末尾（例: "件の図版が見つかりました"） |
| `clear_filters` | フィルタークリアボタンのラベル |

#### `ui_texts.inspector_label` （必須キー）

| キー | 説明 |
|:---|:---|
| `heading` | 見出し |
| `description` | 説明文 |
| `duplicate_warning` | 重複検出時の警告メッセージ |
| `duplicate_blocked` | 重複により保存がブロックされた時のメッセージ |
| `duplicate_title` | 重複先を表示する際の見出し |
| `duplicate_edit` | 既存レコード編集へのリンクラベル |

例：

```yaml
ui_texts:
  search:
    page_title: "画像を検索"
    heading: "画像を検索"
    description: "キーワードやフィルターで検索できます。"
    placeholder: "キャプション、ラベル、コレクション名で検索..."
    empty_filtered: "条件に一致する図版が見つかりませんでした。"
    empty_filtered_hint: "検索条件を変更してみてください。"
    empty_initial: "まだ図版が登録されていません。"
    empty_initial_hint: "Inspector から図版を登録してください。"
    result_none: "結果なし"
    result_suffix: "件の図版が見つかりました"
    clear_filters: "✕ フィルターをクリア"

  inspector_label:
    heading: "図版の情報を入力してください"
    description: "各フィールドに情報を入力してください。"
    duplicate_warning: "同じラベルが見つかりました"
    duplicate_blocked: "⚠️ 重複ラベルがあります。"
    duplicate_title: "重複先:"
    duplicate_edit: "既存レコードを更新"
```

### 重複検出設定 (`duplicate_identity`)

同一リソース（例：同じコレクション内での同じラベル）の重複を検出するための設定。

| キー | 型 | 必須 | 説明 |
|:---|:---|:---:|:---|
| `profile_key` | string | ✅ | プロファイルの識別キー。DB 予約テーブルで重複登録を防ぐために使用 |
| `scope_field` | string | ✅ | スコープの軸となるフィールド。`metadata_fields` 内で定義されている必要があります |
| `label_field` | string | | 重複判定に使用するラベルフィールド。省略時は `label` |
| `duplicate_label_error` | string | ✅ | 重複検出時のエラーメッセージ |

例：

```yaml
duplicate_identity:
  profile_key: "yaml_archive"
  scope_field: collection
  label_field: label
  duplicate_label_error: "このコレクションでそのラベルは既に登録されています"
```

## DB カスタムフィールドとの共存

YAML プロファイルで定義されたフィールドキーと同じキーの DB カスタムフィールドを作成することはできません。例えば `field: collection` と定義した場合、別途カスタムフィールド `collection` を作成しようとするとエラーが発生します。

## OTP リリース時の注意

OTP リリースにおいて `OMNI_ARCHIVE_PROFILE_YAML` を指定する場合は、**必ず絶対パス**を使用してください。相対パスはリリース実行時の作業ディレクトリに依存し、ファイルが見つからなくなる可能性があります。

```bash
# 推奨: 絶対パス
export OMNI_ARCHIVE_PROFILE_YAML=/opt/omni_archive/profiles/production.yaml
_build/prod/rel/omni_archive/bin/server

# 非推奨: 相対パス（動作保証外）
export OMNI_ARCHIVE_PROFILE_YAML=priv/profiles/production.yaml
_build/prod/rel/omni_archive/bin/server
```

> **注意**: `yaml_elixir` の内部依存 `:yamerl` は `mix.exs` の `extra_applications` に含まれており、本番環境でも使用可能です。

## サンプル

完全なサンプルプロファイルは `priv/profiles/example_profile.yaml` を参照してください。
