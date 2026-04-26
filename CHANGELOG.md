# Changelog / 変更履歴

All notable changes to this project are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

このプロジェクトの主要な変更はすべてここに記録されます。
[Semantic Versioning](https://semver.org/lang/ja/) に準拠しています。

---

## [0.2.25] - 2026-04-27

_Summary: Hardens security-sensitive routes, LiveView events, private upload delivery,
IIIF access, dynamic metadata keys, PDF processing limits, and crop geometry input._

### 🔐 セキュリティ強化

- **旧 `/lab/approval` ルートを無効化**
  - 承認操作は Admin 専用の `/admin/review` に集約。
  - 旧 Lab approval ルートはログイン済みユーザーでも到達不能に変更。
- **`priv/static/uploads` の直接公開を停止**
  - `uploads` を `Plug.Static` の配信対象から除外。
  - Lab ページ画像は `/lab/uploads/pages/:pdf_source_id/:filename` の認証・所有者確認付き controller 経由で配信。
- **公開 Gallery / IIIF / Download の公開状態チェックを強化**
  - Gallery の LiveView `select_image` は `published` 画像のみ選択可能。
  - IIIF Image API と `/download/:id` は公開済み画像のみ配信。
  - IIIF Image API は `region` / `size` / `rotation` / `quality.format` を明示検証し、不正値を 400 として扱う。
- **route/event ID の nil-safe 化**
  - 公開 `/download/:id`、IIIF Presentation、Lab/Admin LiveView の route/event ID を完全一致の正整数として検証。
  - 不正 ID や未存在 ID は 404/flash に変換し、`Repo.get!` 由来の 500 を回避。
- **LiveView 入力境界の強化**
  - Admin review/dashboard/custom fields/user/trash、Lab project、Inspector browse/crop/label/finalize/upload で不正イベント入力を通常分岐で処理。
  - `switch_tab` は allowlist によるタブ選択に変更。
- **クロップ geometry 制限**
  - Crop LiveView の `preview_crop` / `save_crop` / `update_crop_data` / `proceed_to_label` で geometry を検証。
  - polygon は最大 64 点、座標は 0..20,000px、矩形辺は 1..20,000px、bbox 面積は 100,000,000px 以下に制限。
- **動的 atom 生成の廃止**
  - YAML / DB カスタムフィールド由来のフィールドキーを string のまま処理。
  - validation rule / facet / duplicate identity は定義済みフィールド参照のみ許可。
- **PDF 処理クォータ・タイムアウト**
  - PDF ページ数、外部コマンド時間、生成 PNG 総量、ユーザー別処理中ジョブ、24時間アップロード件数を制限。

### 📚 ドキュメント

- `security_best_practices_report.md` を現状の実装に合わせて更新。
- `README.md` / `ARCHITECTURE.md` / `IIIF_SPEC.md` / `PROFILES.md` / `DEPLOYMENT.md` に、非公開 uploads、公開済み画像限定配信、route/event ID 検証、crop geometry 制限、YAML string key 方針を追記。

---

## [0.2.24] - 2026-04-26

_Summary: Switches the built-in default domain profile from `Archaeology` to
`GeneralArchive` so a fresh install starts with a profile suited to general
archives. `Archaeology` remains available as an opt-in profile. The factory
becomes profile-aware and Archaeology-flavored tests opt in via
`put_domain_profile/1` to preserve coverage of both profiles._

### 🔄 デフォルトドメインプロファイルの切替 (Archaeology → GeneralArchive)

- **`config/config.exs` のデフォルト変更**
  - `domain_profile` を `OmniArchive.DomainProfiles.Archaeology` から
    `OmniArchive.DomainProfiles.GeneralArchive` に変更。
  - 汎用アーカイブ向けメタデータ（summary / label / collection / item_type /
    date_note）が新規プロジェクトのデフォルトに。
- **`OmniArchive.DomainProfiles` の `@default_profile` 更新 (`domain_profiles.ex`)**
  - alias と `@default_profile` を `GeneralArchive` に切替。`@compile_time_default_profile`
    は `@default_profile` を参照しているため自動的に追従。
- **`CustomMetadataField` の予約キーフォールバック更新 (`custom_metadata_field.ex`)**
  - `Application.get_env(:omni_archive, :domain_profile, ...)` のフォールバックを
    `GeneralArchive` に変更。

### ✅ テストスイートの GeneralArchive 既定対応

- **`test/support/factory.ex` のプロファイル対応化**
  - `extracted_image_attrs/1` のデフォルト `label` がアクティブプロファイルの
    検証ルールに合わせて自動選択（Archaeology は `fig-N-N`、それ以外は
    `item-N-N` slug）。`default_factory_label/0` プライベートヘルパーを追加。
- **Archaeology 前提テストの opt-in 化（13 ファイル）**
  - `OmniArchive.DomainProfileTestHelper.put_domain_profile/1` を module-level
    `setup` ブロックで呼び出すパターンを採用。
  - 対象: `extracted_image_test`, `extracted_image_metadata_test`,
    `duplicate_lookup_test`, `duplicate_identity_test`,
    `extracted_image_dedupe_test`, `inspector_live/label_test`,
    `inspector_live/finalize_test`, `admin/admin_review_live_test`,
    `gallery_live_test`, `approval_live_test`, `search_live_test`,
    `iiif/presentation_controller_test`, `search_test`。
  - `put_domain_profile` が global Application env を変更するため、対象の
    LiveView / Controller テスト 5 ファイルを `async: true → false` に変更。
- **デフォルト検証テストの反転**
  - `domain_profiles_test.exs` を完全書き換えし、`current() == GeneralArchive`、
    `search_facets()` の `[:collection, :item_type, :date_note]`、
    `profile_key() == "general_archive"` を検証。
  - `general_archive_test.exs` の「Archaeology デフォルトは維持される」を
    「デフォルトは GeneralArchive」に反転。Archaeology は明示 opt-in テストで
    別途検証。
- **CRUD/検索テストの label 機械置換**
  - `ingestion_test.exs` の `fig-N-N` ラベルを `item-N-N` に置換
    （label が assertion の主対象でない CRUD テスト）。

### 📚 ドキュメント更新

- **`README.md`**: 利用可能 profile 一覧で「(デフォルト)」マーカーを
  `GeneralArchive` 側に移動。Archaeology を使う場合の `config/config.exs`
  追記方法を明記。
- **`CLAUDE.md`**: 設定例と「Built-in」リストを `GeneralArchive` 中心の
  記述に更新。

### ⚙️ その他

- **`mix.exs` バージョン更新 (0.2.23 → 0.2.24)**
- **`mix review` 全 phase pass**: db version / compile --warnings-as-errors /
  credo --strict / sobelow / dialyzer すべて緑。`mix test` 402 件 0 failures。

### ⚠️ 移行ガイド

既存の Archaeology 利用ユーザーがアップグレードする場合、`config/config.exs` に
以下を明示的に追加して従来挙動を維持してください:

```elixir
config :omni_archive, domain_profile: OmniArchive.DomainProfiles.Archaeology
```

DB データは profile 非依存（`metadata` は `:map` 型 JSONB）のため、マイグレーション
不要。テスト側は本リリースで Archaeology 前提テストへの opt-in が完了済み。

---

## [0.2.23] - 2026-04-16

_Summary: Introduces YAML-based domain profiles so institutions can define metadata
schemas without writing Elixir. Adds `YamlLoader`, a cached `YamlCache` GenServer,
and a runtime-activated `Yaml` profile module._

### 📄 YAML ベースのドメインプロファイル

- **`YamlLoader` モジュールの新設 (`lib/omni_archive/domain_profiles/yaml_loader.ex`)**
  - YAML ファイルをロードし、`metadata_fields` / `validation_rules` / `search_facets` / `ui_texts` / `duplicate_identity` を検証・パース。
  - 正規表現文字列を `Regex.compile!/1` でコンパイルし、フィールドキーの命名規則（小文字・数字・アンダースコア）を強制。
  - `caption` / `label` フィールドの必須チェック、`storage: core` の利用制限、ファセット定義の整合性チェック等を実施。
- **`YamlCache` GenServer の新設 (`lib/omni_archive/domain_profiles/yaml_cache.ex`)**
  - ETS バックの GenServer。アプリ起動時に YAML プロファイルを一度だけロードしてキャッシュ。
  - `OMNI_ARCHIVE_PROFILE_YAML` 環境変数が設定されている場合のみスーパービジョンツリーに追加。
- **`Yaml` プロファイルモジュールの新設 (`lib/omni_archive/domain_profiles/yaml.ex`)**
  - `DomainProfile` ビヘイビアを実装。`YamlCache` に委譲し、組み込みプロファイルと同じインターフェースで利用可能。
- **`runtime.exs` への `OMNI_ARCHIVE_PROFILE_YAML` 環境変数の配線**
  - 環境変数が設定されている場合、`domain_profile: OmniArchive.DomainProfiles.Yaml` を自動選択。
- **アクティブプロファイルキーの DB カスタムフィールド予約**
  - `CustomMetadataField` に予約キーチェックを追加。YAML プロファイル定義済みフィールドと同名の DB カスタムフィールド作成を拒否。
- **サンプルプロファイルの追加 (`priv/profiles/example_profile.yaml`)**
- **ドキュメントの追加 (`PROFILES.md`)**
  - YAML プロファイルの構造・有効化方法・各キーの詳細仕様を記載。

### ⚙️ その他

- **`mix.exs` バージョン更新 (0.2.22 → 0.2.23)**
- **`yaml_elixir` 依存の追加**

---

## [0.2.22] - 2026-03-03

_Summary: Replaces rectangle-based cropping with polygon cropping throughout the
Lab, Gallery, and Admin review UIs. Adds a polygon crop engine to `ImageProcessor`
using SVG masks and white-background compositing for JPEG-compatible output._

### ✂️ 多角形（ポリゴン）クロップ機能の実装
- **クロップ画面 (`crop.ex`) をポリゴン選択 UI に全面移行**
  - 矩形ドラッグ選択から、シングルクリックで頂点を追加し多角形を描画する方式に変更。
  - ダブルクリック（または始点クリック / Enter キー）でポリゴンを閉じて保存。
  - `preview_crop` / `save_crop` イベントが `%{"points" => [...]}` 形式のポリゴン頂点配列に対応。
  - 旧矩形データ（`%{"x", "y", "width", "height"}`）との後方互換性を維持。
  - Undo 機能がポリゴン頂点配列にも対応。クリア（やり直し）ボタンを追加。
  - D-Pad ナッジコントロールはポリゴン全体の移動に使用。
- **`ImageProcessor` にポリゴンクロップエンジンを追加 (`image_processor.ex`)**
  - `crop_image/3` と `crop_to_binary/2` が `%{"points" => [...]}` 形式に対応。
  - SVG マスク + `ifthenelse` 白背景合成戦略を採用。ポリゴン外を純白 (255,255,255) で塗りつぶし。
  - バウンディングボックス計算 → `extract_area` で矩形クロップ → SVG マスク生成 → `ifthenelse` 合成の 4 段階パイプライン。
  - JPEG 互換の 3バンド RGB 画像として出力（アルファチャンネル不要）。
- **`PtiffGenerator` のエラーハンドリング改善 (`ptiff_generator.ex`)**
  - `Image.write_to_file` のエラーを個別に捕捉し、読み込みエラーと書き込みエラーを区別してログ出力。
- **`Pipeline` のポリゴンクロップ対応 (`pipeline.ex`)**
  - `crop_image` 出力パスを `.png` に統一（ポリゴンクロップが PNG 形式で出力するため）。
  - 出力ファイルの存在確認とフォールバック処理を追加。

### 🖼️ ポリゴンクロッププレビュー表示（全画面対応）
- **管理者レビュー画面 (`review_live.ex`) のポリゴン対応**
  - `dims_map` を `preview_map` に置換。各画像に `{orig_w, orig_h, polygon_points_str, bbox}` を保持。
  - SVG `clipPath` + `<polygon>` によるポリゴンマスキングプレビューを実装。
  - Inspector パネルでもポリゴンクロップを正確に表示。
  - 旧矩形データはクリップなしのフォールバック表示。
- **公開ギャラリー (`gallery_live.ex`) のポリゴン対応**
  - `build_preview_map` / `extract_preview_data` によるポリゴンプレビューマップの構築。
  - カード表示・モーダル表示の両方で SVG `clipPath` ポリゴンマスキングを適用。
  - 白背景 `<rect>` を配置し、clipPath 外の領域を白で塗りつぶし。
- **ラベリング画面 (`label.ex`) のポリゴン対応**
  - クロッププレビューに SVG `clipPath` ポリゴンマスキングを適用。
  - `extract_preview_data` / `safe_int` ヘルパーを追加。
- **JS Hook (`image_selection_hook.js`) のポリゴン選択 UI 実装**
  - 矩形選択からポリゴン（多角形）描画モードに全面移行。
  - クリックで頂点追加、ダブルクリック/始点クリック/Enter キーで閉じて保存。
  - リアルタイムのラバーバンド描画とハーベストゴールドのポリゴンスタイル。
  - SVG 暗転マスク（`<polygon>` カットアウト）のリアルタイム更新。

### ⚙️ その他
- **`mix.exs` バージョン更新 (0.2.20 → 0.2.22)**

---

## [0.2.21] - 2026-03-01

_Summary: Unifies IIIF module casing (`OmniArchive.Iiif`), fixes the OpenSeadragon
gallery modal interaction, and resolves routing bugs in IIIF image delivery._

### 🖼️ IIIF モジュール & ギャラリー表示の強化・修正
- **IIIF モジュールの命名規則の統一**
  - モジュールロードエラーを解消するため、ケーシングを `OmniArchive.IIIF` から `OmniArchive.Iiif` に統一。
  - 関連する各ファイル（`OmniArchive.Iiif.PtiffGenerator` など）の `defmodule` および参照を修正し、コンパイルエラー・警告を除去。
- **Gallery モーダルビューア（OpenSeadragon）の改善**
  - HEEx テンプレートを改修し、IIIF マニフェストが存在する場合は OpenSeadragon を、存在しない場合はフォールバック SVG プレビューを正確に出し分けるよう修正。
  - 親コンテナの `pointer-events-none` 制約によるクリック不可状態を解消。
  - `#osd-viewer` 要素の CSS を強制上書きし、OSD キャンバスが全ポインターイベント（ドラッグやズームなど）を正しく捕捉して最前面でインタラクティブに動作するよう修正。
- **OpenSeadragon Hook の初期化ロジック修正 (`app.js`)**
  - 描画タイミングの問題を回避するため、初期化処理を `setTimeout` で遅延実行するよう調整。
  - UI コントロールアイコンのパス (`prefixUrl`) を正しく設定し、ナビゲーションアイコンが正常に表示されるように修正。
  - `destroyed()` コールバックを実装し、遅延処理のキャンセルと OSD インスタンスの破棄 (`destroy()`) を行い、メモリリークを防止。
- **IIIF 画像の表示とルーティングの修正**
  - ギャラリーから画像をクリックして拡大する際のエラーおよび IIIF サーバーとの連動に関する不具合を修正。

---

## [0.2.20] - 2026-03-01

### 🖼️ Lazy PTIFF 生成の実装
- **承認・公開プロセスへの PTIFF 生成の統合 (`ingestion.ex`)**
  - メタデータ保存時の自動生成を廃止し、管理者が「承認 (Approve)」したタイミングで PTIFF を生成する仕組みに移行。
  - 編集中の不要な CPU/ストレージ消費を抑え、リソースを最適化。
- **`OmniArchive.Iiif.PtiffGenerator` モジュールの新設**
  - `vix` (libvips) を使用したスタンドアロンの PTIFF 生成ロジックをカプセル化。
  - `generate_ptiff/2` 関数により、高解像度 PNG からピラミッド TIFF を生成。
- **DEFLATE 可逆圧縮の採用**
  - 線画や図版の品質を保つため、JPEG 圧縮ではなく DEFLATE 圧縮を採用。
  - モスキートノイズを排除し、ディープズーム時でも細い線を鮮明に維持。

### ⚙️ その他
- **`mix.exs` バージョン更新 (0.2.19 → 0.2.20)**

---

## [0.2.19] - 2026-02-24

### ⚡ DB 挿入レイヤーの最適化（Bulk Insert）
- **`Ingestion.bulk_create_extracted_images/1` を新設 (`ingestion.ex`)**
  - `Repo.insert_all/3` を使用して 1 回の SQL INSERT で全 `ExtractedImage` レコードを一括挿入。
  - `insert_all` は Ecto の changeset / auto-timestamp をバイパスするため、`inserted_at` / `updated_at` およびデフォルト値（`status: "draft"`, `lock_version: 1`）を明示的に設定。
  - `returning: true` で挿入後のレコードを取得。
- **`Pipeline` の DB 挿入処理をバルクインサートに移行 (`pipeline.ex`)**
  - 従来の `Task.async_stream` + 個別 `Ingestion.create_extracted_image/1` ループを廃止。
  - `Enum.map` で属性リストを構築後、`Ingestion.bulk_create_extracted_images/1` で一括挿入。
  - DB ラウンドトリップを N 回 → 1 回に削減し、Ecto オーバーヘッドを最小化。
  - 進捗ブロードキャストは挿入後に一括送信する方式に変更。

---

## [0.2.18] - 2026-02-23

### 🚀 GitHub Actions CI パイプライン
- **`.github/workflows/ci.yml` を新設**
  - `push` (main) および `pull_request` をトリガーとした自動品質ゲート。
  - `ubuntu-latest` + PostgreSQL 15 サービスコンテナで実行。
  - Elixir `1.18.x` / OTP `27` をセットアップ（`erlef/setup-beam@v1`）。
  - `deps` / `_build` を `mix.lock` ハッシュでキャッシュし、ビルド高速化。
  - 品質チェックステップ:
    - `mix compile --warnings-as-errors` — 厳格コンパイル（警告ゼロ保証）
    - `mix format --check-formatted` — コードフォーマットチェック
    - `mix test` — ExUnit テスト実行

---

## [0.2.17] - 2026-02-23

### 🎨 PDF カラーモード選択機能
- **Upload 画面にカラーモード切替ラジオボタンを追加 (`upload.ex`)**
  - 「🖤 モノクロモード（高速）」と「🎨 カラーモード（標準）」の 2 モード切替 UI を追加。
  - デフォルトは「モノクロ」（`-gray` フラグ付き `pdftoppm` でグレースケール変換し高速化）。
  - `phx-change="validate"` でラジオ選択値を LiveView assigns (`color_mode`) に反映。
  - `phx-submit="upload_pdf"` 時にカラーモードを `UserWorker` に伝搬。
- **`UserWorker.process_pdf/4` → `process_pdf/5` にカラーモード引数を追加 (`user_worker.ex`)**
  - GenServer cast メッセージに `color_mode` パラメータを追加。
  - `Pipeline.run_pdf_extraction/4` の `opts` に `color_mode` を含むよう変更。
- **`Pipeline` からのカラーモード伝搬 (`pipeline.ex`)**
  - `PdfProcessor.convert_to_images/3` 呼び出し時に `color_mode` を `processor_opts` に含めて伝搬。
- **`PdfProcessor` にカラーモード対応ロジックを追加 (`pdf_processor.ex`)**
  - `run_pdftoppm_chunk/4` → `run_pdftoppm_chunk/5` に `opts` 引数を追加。
  - `color_mode == "mono"` の場合は `pdftoppm` に `-gray` フラグを付与（グレースケール変換で高速化）。
  - `color_mode == "color"` の場合はフラグなし（フルカラー出力）。
- **カラーモードセレクター CSS の追加 (`inspector.css`)**
  - `.color-mode-selector`, `.color-mode-option`, `.color-mode-label` 等のスタイルを追加。
  - 選択中のモードにゴールドアクセントのハイライトを適用。

---

## [0.2.16] - 2026-02-23

### 🔄 PDF チャンク進捗のリアルタイム表示
- **`PdfProcessor` に進捗ブロードキャスト機能を追加 (`pdf_processor.ex`)**
  - `convert_to_images/2` → `convert_to_images/3` に `opts` 引数（`%{user_id: ...}`）を追加。
  - チャンク変換完了ごとに `broadcast_chunk_progress/3` で `{:extraction_progress, current_page, total_pages}` を PubSub に配信。
  - `user_id` が `opts` に含まれない場合は安全にスキップ（no-op）。
- **`Pipeline` からの `user_id` 伝播 (`pipeline.ex`)**
  - `PdfProcessor.convert_to_images/3` 呼び出し時に `%{user_id: opts[:owner_id]}` を渡すように変更。
- **Upload 画面にプログレスバー UI を追加 (`upload.ex`)**
  - `current_page` / `total_pages` assigns を追加し、チャンク進捗を LiveView 状態で管理。
  - `handle_info({:extraction_progress, current, total}, socket)` コールバックで進捗を受信。
  - アップロード中かつ `total_pages > 0` の場合、ページ数とパーセンテージ付きのプログレスバーを表示。
  - 抽出完了時（`{:extraction_complete, ...}`）にカウンターをリセット。

---

## [0.2.15] - 2026-02-23

### ⚡ パフォーマンス最適化
- **libvips グローバル制約の導入 (`application.ex`)**
  - `Vix.Vips.concurrency_set(1)` — Elixir 側で並行処理を管理するため、libvips 内部のスレッド競合を防止。
  - `Vix.Vips.cache_set_max(100)` / `cache_set_max_mem(512MB)` — libvips キャッシュの上限を設定し、VPS 環境でのメモリ使用量を制限。
- **PDF チャンク逐次処理 (`pdf_processor.ex`)**
  - 大規模 PDF（200+ ページ）でも OOM を起こさないよう、10 ページ単位のチャンクに分割して逐次処理する方式に変更。
  - `pdfinfo` でページ数を事前取得し、`Task.async_stream(max_concurrency: 1)` で順次変換。
  - 変換ロジックを `run_chunked_conversion/4`, `build_chunks/1`, `run_pdftoppm_chunk/5`, `collect_and_rename_images/1` 等のプライベート関数に分割し、可読性を向上。

### 📝 コード品質
- **`UserWorker` に `@moduledoc` を追加**
  - モジュールの責務と位置づけを明記するドキュメントを追加。

### ✅ テスト安定化
- **`pipeline_test.exs` の `Task.start` → `Task.async` + `await` 移行**
  - テスト終了後に Task が残り `StaleEntryError` が発生する問題を修正。`Task.async/1` + `Task.await/2` で完了を保証するパターンに変更。
  - `refute_receive` のタイムアウトを 2000ms → 500ms に短縮（`Task.await` で完了保証済みのため）。
- **`user_registration_controller_test.exs` の `~p` シジル置換**
  - 招待制移行によりコメントアウト済みの `/users/register` ルートに対して `~p` シジルがコンパイル時ルート検証で warning を出す問題を修正。通常の文字列リテラルに置換。

---

## [0.2.14] - 2026-02-23

### ⚙️ OTP バックグラウンド処理基盤の導入
- **ユーザー専属 `UserWorker` (GenServer) の新設**
  - `lib/omni_archive/workers/user_worker.ex` を新設。ユーザーごとに 1 プロセスが起動し、PDF 処理を裏側で実行。
  - `Registry` (`OmniArchive.UserWorkerRegistry`) と `DynamicSupervisor` (`OmniArchive.UserWorkerSupervisor`) をスーパービジョンツリーに追加し、プロセスの名前解決と動的起動を実現。
  - `start_user_worker/1` — ユーザー ID に紐づくワーカーを起動。
  - `process_pdf/4` — GenServer に PDF 処理を非同期に委譲 (`cast`)。
- **LiveView からの同期処理の排除 (Upload 画面)**
  - `InspectorLive.Upload` での PDF 処理を `Task.start` から `UserWorker.process_pdf/4` への委譲に移行。
  - 処理完了を PubSub (`{:extraction_complete, pdf_source_id}`) で受信し、UI を自動更新。
  - 処理中は `uploading: true` のままスピナーを表示し、完了後に Browse 画面へ遷移。
- **PubSub 完了通知の追加 (Pipeline)**
  - `Pipeline.run_pdf_extraction/4` の成功パスで `{:extraction_complete, pdf_source.id}` を `pdf_pipeline:{owner_id}` トピックに配信。
  - `Pipeline.pdf_pipeline_topic/1` ヘルパー関数を追加。
- **ワーカー自動起動 (UserAuth)**
  - `user_auth.ex` の `mount_current_user` フック内で、認証済みユーザーの `UserWorker` を自動起動。既に起動済みの場合は安全に無視。

### ✅ テスト
- **PubSub ブロードキャストテストの追加**
  - `pdf_pipeline_topic/1` のトピック名生成テスト。
  - `run_pdf_extraction/4` 成功時に `{:extraction_complete, pdf_source_id}` が配信されることの検証。
  - エラー時および `owner_id` 未指定時に完了通知が配信されないことの検証。

---

## [0.2.13] - 2026-02-23

### 🐛 バグ修正 & 改善
- **メタデータ入力のバリデーション強化**
  - `site` / `period` / `artifact_type` の文字数制限を 30文字 に厳格化。
  - フロントエンドの `maxlength` 属性を削除し、サーバーサイドバリデーションによる日本語のエラーメッセージをUIに明示するよう改善。
- **データベースシーディングの修正**
  - `mix ecto.setup` 時、管理者 (`admin@example.com`) に確実に `admin` ロールが付与されるよう修正。
  - 権限テスト用に一般ユーザー (`user@example.com` / `Password1234!`) も自動作成するよう追加。

### 🛠️ コード品質の改善 (Credo 対応)
- **`label.ex` のリファクタリング**
  - `mix review`（Credo）の警告に対処するため、`LabelLive` モジュール内の `run_inline_validation/3` および `do_save/2` の Cyclomatic Complexity（複雑度）を削減。関数を適切に分割し、可読性と保守性を向上。

---

## [0.2.12] - 2026-02-21

### 🔐 セキュリティ強化 & バリデーション
- **メタデータ入力への長さ制限を追加**
  - `extracted_images` の `caption` (1000文字)、`site` / `period` / `artifact_type` (各100文字) に `validate_length` バリデーションを追加。
  - Lab ラベリング UI (`LabelLive`) の各入力フィールドに `maxlength` 属性を追加し、フロントエンドとバックエンドの両面で制限を適用。
- **XSS およびリソース枯渇攻撃への対策**
  - 自由入力フィールドへの厳格な長さ制限により、意図しない大量データ投入を防止。

### 🛠️ コード品質の改善 (Credo 対応)
- **命名規則の修正**
  - `ExtractedImage` および `PdfSource` の `is_published?/1` ヘルパーを、Elixir の慣習に従い `published?/1` にリネーム。
- **パフォーマンス計測と最適化**
  - HEEx テンプレート内での `Enum.count/1` や `length/1` の多用を避け、適切なガード条件や計算済みフィールドの使用へ移行。
- **デッドコードの削除**
  - 使用されていない一時的な関数や不要なプロトタイプコードをクリンアップ。

### 👤 ユーザースコーピングの強化
- **PdfSource のオーナーシップ完全隔離**
  - 管理者以外のユーザーが、URL 直打ち等で他人のプロジェクト（`pdf_sources`）にアクセスすることを完全に遮断。
  - `Ingestion.get_pdf_source!/2` において、常に `user_id` によるフィルタリングを強制。

---

## [0.2.11] - 2026-02-20

### 🔐 権限管理 (RBAC) & アクセス制御の強化
- **`PdfSource` のオーナーシップ管理とマルチユーザーデータ隔離**
  - `pdf_sources` テーブルに `user_id` カラムを追加し、プロジェクトの「所有者」を明確化。
  - `Ingestion` コンテキストにおけるフェッチ処理（`get_pdf_source!/2`、`list_pdf_sources/1`）をすべて `user_id` による厳密なスコーピングに移行。
  - Lab 全面（一覧、閲覧、クロップ、ラベリング、アップロード）で、Admin は全データ、一般ユーザーは「自身のプロジェクト」のみアクセス・編集可能に制限。
  - 不正なアクセス（他人のプロジェクトを開こうとする等）に対し `Ecto.NoResultsError` を返し、404 Not Found として安全に処理されるよう改修。
  - マイグレーション: `add_user_id_to_pdf_sources`

---

## [0.2.10] - 2026-02-19

### 📋 プロジェクト ワークフローステータス管理
- **`PdfSource` にワークフローステータスを追加**
  - `workflow_status` カラム（`wip` / `pending_review` / `returned` / `approved`）を追加。プロジェクト単位で作業進捗を管理。
  - `return_message` カラム（`text`）を追加。管理者が差し戻し時にプロジェクト全体へのメッセージを記録可能に。
  - マイグレーション: `add_workflow_status_to_pdf_sources`
- **ワークフロー遷移関数の実装**
  - `Ingestion.submit_project/1` — `wip` / `returned` → `pending_review`。提出時に `return_message` を自動クリア。
  - `Ingestion.return_project/2` — `pending_review` → `returned`。差し戻しメッセージを保存。
  - `Ingestion.approve_project/1` — `pending_review` → `approved`。
  - 不正な遷移は `{:error, :invalid_status_transition}` を返却。
- **Lab UI のワークフロー表示**
  - プロジェクトカードにワークフローステータスバッジを追加（作業中 / 作業完了/審査待ち / ⚠️ 差し戻しあり / 承認済み）。
  - `wip` / `returned` ステータス時に「✅ 作業完了として提出」ボタンを表示。
  - 差し戻しメッセージをプロジェクトカード内にアラートとして表示。

### 🔔 差し戻し理由の表示改善
- **ラベリング画面 (`/lab/label/:image_id`) の改善**
  - プロジェクトレベルの差し戻し（`workflow_status == "returned"`）でも差し戻しアラートを表示するよう拡張。
  - 管理者からの全体コメント（`return_message`）と個別画像コメント（`review_comment`）を分離表示。
  - 差し戻し理由ボックスの視覚的スタイリング（赤色左ボーダー・背景色）を追加。
- **Inspector 画面での差し戻し理由表示**
  - Browse 画面でプロジェクトレベル・画像レベルの差し戻し理由を確認可能に。

### 👤 オーナーメール表示（Admin 向け）
- **Lab プロジェクト一覧にオーナーメールアドレスを表示**
  - `list_pdf_sources/1` クエリに所有者情報を結合。`owner_email` バーチャルフィールドとして取得。
  - Admin ロールの場合のみ、プロジェクトカードにオーナーのメールアドレスを表示。

### 🔀 ルーティング改善
- **`/admin` → `/admin/review` リダイレクト**
  - `/admin` 直接アクセス時にデフォルトの Phoenix "Available routes" ページが表示されないよう、`/admin/review` へリダイレクトする `PageController.redirect_admin` アクションを追加。

### ✅ テスト
- **ワークフロー遷移テストの追加**
  - `submit_project/1`、`return_project/2`、`approve_project/1` の正常遷移・不正遷移テストを網羅的に追加（13テストケース）。

---

## [0.2.9] - 2026-02-18

### 🗑️ ソフトデリート & ゴミ箱管理
- **ソフトデリート機能の実装**
  - `PdfSource` スキーマに `deleted_at` カラム（`utc_datetime`）を追加。`nil` = アクティブ、値あり = ゴミ箱内。
  - `soft_delete_pdf_source/1` — `deleted_at` を現在時刻に設定し、物理ファイルは保持。
  - `restore_pdf_source/1` — `deleted_at` を `nil` に戻してプロジェクトを復元。
  - `hard_delete_pdf_source/1` — 既存の `delete_pdf_source/1` をリネーム。物理ファイル・DB レコードを完全削除。
  - `list_deleted_pdf_sources/0` — ソフトデリート済みプロジェクト一覧を取得（Admin ゴミ箱用）。
  - `list_pdf_sources/1` — ソフトデリート済みレコードを自動除外するフィルタを追加。
  - マイグレーション: `add_deleted_at_to_pdf_sources`
- **Admin ゴミ箱画面 (`/admin/trash`) の新設**
  - ソフトデリート済みプロジェクトをテーブル形式で一覧表示。
  - ♻️ 復元ボタン: プロジェクトを Lab 一覧に戻す。
  - 💀 完全削除ボタン: 確認ダイアログ付きの物理ファイル・DB レコード完全削除。
  - ローカルステート更新による即時 UI 反映。
  - 管理者タブレイアウトにゴミ箱タブを追加。

### 🔒 公開済みプロジェクトの削除防止
- **`is_published?/1` ヘルパーの追加**
  - PdfSource に紐づく `ExtractedImage` に `published` ステータスが存在するか判定。
- **ソフトデリートの安全ガード**
  - 公開済み画像を含むプロジェクトの削除を `{:error, :published_project}` で拒否。
- **Lab UI の保護表示**
  - 公開済みプロジェクトに 🔒 ロックアイコンを表示。
  - 削除ボタンを無効化し、ツールチップで理由を表示。

### 🐛 Lab 画面の改善
- **Draft 選択時のナビゲーション修正**
  - 「Draft」ボタンクリック時にラベリング画面ではなくクロップ画面へ遷移するよう修正。
- **Lab ステータス表示の修正**
  - `/lab` ディレクトリ内のステータス表示を「作業完了」から「取り込み完了」に変更。

---

## [0.2.8] - 2026-02-18

### 📁 Lab プロジェクト管理
- **プロジェクト一覧画面 (`/lab`) の新設**
  - PdfSource をカード形式で一覧表示。ファイル名、ページ数、画像数、ステータスを視覚的に表示。
  - RBAC 対応: Admin は全プロジェクト、一般ユーザーは自分の画像があるプロジェクトのみ表示。
  - カード UI にステータスバッジ（uploading / converting / ready / error）を表示。
  - プロジェクト削除機能（物理ファイル・関連画像ごとカスケード削除）。
- **プロジェクト詳細画面 (`/lab/projects/:id`) の新設**
  - PdfSource に紐づく画像をサムネイルグリッドで表示。各画像のラベル・ステータスを表示。
  - 画像がない場合の再処理（Re-process）ボタンを提供。
  - 所有権チェック付き PdfSource 取得（一般ユーザーは自分のプロジェクトのみ閲覧可能）。
- **`Ingestion` コンテキスト拡張**
  - `list_pdf_sources/1` — RBAC 対応の PdfSource 一覧（画像数を `select_merge` で集計）。
  - `get_pdf_source!/2` — 所有権チェック付き取得。
  - `reprocess_pdf_source/2` — PDF 再抽出の非同期実行。
  - `delete_pdf_source/1` — `Ecto.Multi` トランザクションによるカスケード削除。
- **`PdfSource` スキーマ変更**
  - `image_count` バーチャルフィールドを追加。
- **Lab 専用 CSS (`lab.css`) の追加**
  - プロジェクトカード・画像グリッド・ステータスバッジ・ボタン等のスタイルを定義。
  - Harvest Gold アクセントカラーによるホバーエフェクト。
  - モバイルレスポンシブ対応。
- **ルーター変更**
  - `/lab` → `LabLive.Index`（プロジェクト一覧）に変更。
  - `/lab/upload` → `InspectorLive.Upload`（アップロード画面の URL 変更）。
  - `/lab/projects/:id` → `LabLive.Show`（新規）。

### ⚡ パフォーマンス改善
- **Admin Dashboard の非同期データロード**
  - `mount/3` で空リストを即返却し、`handle_info(:load_images, ...)` でバックグラウンドロード。ローディングスピナー UI を追加。
- **削除操作のローカルステート更新**
  - 単体削除・一括削除後に全件 `list_extracted_images/1` を再取得する処理を廃止。`Enum.reject` によるローカルフィルタリングに置換し、レスポンスを高速化。
- **`list_extracted_images/1` のクエリ最適化**
  - `Repo.preload(:owner)` を後処理から Ecto クエリ内の `preload:` オプションに移動し、N+1 問題を解消。

### 🔐 権限管理 (RBAC) & ユーザー管理
- **ロールベースアクセス制御 (RBAC) の導入**
  - `User` スキーマに `role` カラム (`admin` / `user`) を追加。
  - `Ingestion` コンテキストにおいて、ロールに応じたデータフィルタリングを実装（Admin は全件、一般ユーザーは自身のデータのみ）。
  - 管理者専用の権限チェックプラグをルーターに適用。
- **ユーザー登録モデルの刷新**
  - 公開ユーザー登録を廃止し、管理者による招待/作成モデルへ移行。
  - 管理者専用のユーザー管理画面 (`/admin/users`) を実装。
  - ユーザー削除機能の実装（自分自身の削除防止ロジック付き）。
- **認証体験の改善**
  - メール確認ステップをスキップし、即時ログインを許可するよう調整。

### 🛠️ 管理者機能 & UI
- **Admin Dashboard の強化**
  - 全ユーザーがアップロードした画像の一覧表示・管理に対応。
  - **一括削除（Bulk Delete）機能**の実装。複数項目を選択して DB レコードと物理ファイルを一括削除可能に。
  - 共通の管理者用タブレイアウト (`AdminLayout`) を導入し、ダッシュボード・ユーザー管理・レビュー画面間のナビゲーションを統合。
- **UI コンポーネントのクリーンアップ**
  - デフォルトの Phoenix ヘッダーを廃止し、アプリ固有のミニマルなナビゲーションへ移行。
  - モダルウィンドウの安定性向上（LiveView の DOM パッチによる意図しないクローズを防止）。

---

## [0.2.7] - 2026-02-17

### 🔐 認証システム (phx.gen.auth)
- **ユーザー認証基盤の全面導入**
  - `phx.gen.auth` によるセッションベース認証を実装（`bcrypt_elixir`）。
  - `User` / `UserToken` スキーマ、`Accounts` コンテキストを追加。
  - ログイン (`/users/log-in`)、ユーザー登録 (`/users/register`)、設定 (`/users/settings`) の各画面を実装。
  - マイグレーション: `create_users_auth_tables`
- **ルーター保護**
  - `/lab/*` および `/admin/*` スコープに `require_authenticated_user` プラグを適用。
  - 未ログインユーザーはログイン画面にリダイレクト。
- **グローバルナビゲーションバー**
  - `root.html.heex` にアプリ共通のナビバーを追加（Deep Indigo & Harvest Gold テーマ）。
  - ログイン状態に応じてメールアドレス・設定・ログアウト / 登録・ログインを動的に表示。
- **シードデータ**
  - `seeds.exs` にデフォルト管理者ユーザー (`admin@example.com` / `password1234`) の自動作成処理を追加。

### 👥 所有者/作業者モデル
- **`ExtractedImage` に所有権カラムを追加**
  - `owner_id` — アップロードした人（所有者）
  - `worker_id` — 現在編集中の人（作業者）
  - `list_all_images_for_lab/1` が `owner_id` / `worker_id` によるフィルタに対応。
  - マイグレーション: `add_ownership_to_extracted_images`

### ⚙️ Pipeline 並行安全性の改善
- **ジョブ固有一時ディレクトリの導入**
  - PDF 変換時にジョブごとのユニーク一時ディレクトリ (`omniarchive_job_{uuid}`) を使用。
  - `try/after` パターンで一時ディレクトリの確実なクリーンアップを保証。
  - 並行実行される複数パイプラインジョブ間でのファイル衝突を防止。

### 🐛 バグ修正 & 安定性向上
- **抽出画像の並び順を保証**
  - `Ingestion.list_extracted_images/1` に `page_number` 昇順のソート条件を追加。
  - データベースの挿入順序に依存せず、常にページ順で画像が取得されるよう修正。
- **テストデータの整合性向上**
  - `ingestion_test.exs` において、ラベル形式（`fig-{number}-{number}`）とユニーク制約を遵守するようテストデータを修正。


### 🛡️ データ整合性 & 排他制御
- **楽観的ロック (Optimistic Locking) の導入**
  - `extracted_images` テーブルに `lock_version` カラムを追加。
  - 同時編集時の競合を検知し、`StaleEntryError` をハンドリング。
  - 競合発生時はユーザーにアラートを表示し、上書きを防止 ("Someone else has updated this image...")。
  - マイグレーション: `add_lock_version_to_extracted_images`

### 🎨 UI 改善
- **却下（Rejected）リストの視認性向上**
  - "Fix Required" タブのリストレイアウトを刷新。
  - レビューコメントを独立した行（2行目）に表示し、長いコメントも全文表示可能に。
  - 視覚的な分離（背景色・ボーダー）により、修正理由を明確化。


### 🖼️ IIIF Presentation API 3.0 — PdfSource 単位 Manifest
- **PdfSource（資料）単位の IIIF Manifest 生成を実装**
  - エンドポイント: `GET /iiif/presentation/:source_id/manifest`
  - PdfSource に紐づく公開済み（`published`）画像を page_number 昇順で Canvas に集約
  - Canvas のサイズは `geometry` の `width`/`height` から取得（フォールバック: 1000×1000）
  - CORS ヘッダー・`application/ld+json` Content-Type に対応
  - Mirador 等の標準 IIIF ビューアで閲覧可能

### 🔄 Fix & Resubmit ワークフロー
- **差し戻し・再提出フローを実装**
  - `rejected` ステータスを `extracted_images.status` に追加（`draft` / `pending_review` / **`rejected`** / `published` / `deleted`）
  - `review_comment` カラムを追加（差し戻し理由の専用保存。従来の caption 追記方式を廃止）
  - `Ingestion.resubmit_image/1` — 再提出（`rejected` → `pending_review`、`review_comment` クリア）
  - `Ingestion.list_rejected_images/0` — 差し戻し済み画像一覧
  - Upload 画面（Step 1）に「要修正（差し戻し）」タブを追加
  - Label 画面（Step 4）に差し戻しアラートと「再提出する」ボタンを実装
  - マイグレーション: `add_review_comment_and_rejected_status`

### 📁 ファイルバージョニング
- **アップロードファイル名にタイムスタンプを付与**
  - `filename-{unix_timestamp}.ext` 形式でブラウザキャッシュ衝突を防止
  - 同名ファイルの再アップロード時にも一意性を保証

### 🧹 開発環境: アップロードディレクトリの自動クリーンアップ
- `seeds.exs` に `priv/static/uploads` の自動削除・再作成処理を追加
  - `Mix.env() == :dev` の場合のみ実行
  - DB リセット時の「ゴーストデータ」（孤立ファイル）を防止

### 🛠️ コンテキスト追加
- `Ingestion.list_published_images_by_source/1` を追加（IIIF Manifest 用）
- `Ingestion.resubmit_image/1` を追加（再提出用）
- `Ingestion.list_rejected_images/0` を追加（要修正タブ用）

---

## [0.2.5] - 2026-02-14

### 🖼️ ギャラリー画像拡大モーダル
- **クリックで拡大表示モーダルを実装**
  - ギャラリーカードをクリックすると、SVG `viewBox` を使用した高精度な拡大表示モーダルを表示。
  - `Esc` キーまたは背景クリックでモーダルを閉じる操作に統一（閉じるボタンは廃止）。
  - 検索バー上に使用方法ガイド（「図版をクリックして拡大表示 | Esc キーで閉じる」）を追加。

### 🐛 UI 安定化: カードホバーちらつき修正
- **ギャラリー (`gallery.css`) および管理画面 (`admin-review.css`) のカードホバーエフェクトを安定化**
  - `transform: translateY()` や `scale()` によるちらつきを解消。
  - ホバー時は `border-color` の変更のみに簡素化。
  - `will-change: transform` を追加し GPU レンダリングヒントを付与。
  - 画像の `transform: scale(1.05)` ホバーエフェクトを撤廃し、安定した表示を確保。
- **Masonry レイアウト (Pinterest 風グリッド)**
  - CSS Multi-column を採用し、アスペクト比の異なる画像を隙間なく自然に配置。
  - `break-inside: avoid` によりカードの途切れを防止。

---

## [0.2.4] - 2026-02-14

### 🐛 重大バグ修正: ゴーストレコード & データ消失
- **Write-on-Action ポリシーの導入**
  - Browse（Step 2）でページ選択時に `ExtractedImage` レコードを自動作成していた問題を修正。
  - レコードは Crop（Step 3）でユーザーがダブルクリックでクロップを保存した時に初めて作成されるように変更。
- **Crop ルーティングの変更**
  - `/lab/crop/:image_id` → `/lab/crop/:pdf_source_id/:page_number` に変更。
  - Crop 画面は既存レコードがあればロードし、なければ `save_crop` 時に新規作成。
- **Label での geometry バリデーション追加**
  - geometry（クロップ範囲）が未設定の場合、保存をブロックするバリデーションを追加。
- **Admin Review の壊れたレコードフィルタリング**
  - `list_pending_review_images` クエリに `image_path`/`geometry` の nil チェックを追加。

### ⚠️ 破壊的変更
- Crop 画面の URL パターンが変更されました（`/lab/crop/:image_id` → `/lab/crop/:pdf_source_id/:page_number`）。

---

## [0.2.3] - 2026-02-14

### 🎨 UI & レンダリング改善
- **SVG `viewBox` 方式による精密なクロップ表示を採用**
  - 公開ギャラリー (`/gallery`) および管理画面 (`/admin/review`) のカードにおいて、アスペクト比を維持した精密なプレビューを実現。
  - 背景をダークネイビーに統一し、余白が発生した場合も視覚的な整合性を維持。
- **ナッジコントロール（D-Pad）のスタイル刷新**
  - ゴールド枠＋透明背景のデザインに変更し、視認性とモダンな操作感を向上。
  - ホバー時にゴールドで塗りつぶされるインタラクティブなフィードバックを追加。

### 🛠️ 機能追加
- **管理画面での図版削除機能の実装**
  - `/admin/review` に「削除（ソフトデリート）」ボタンを追加。誤登録エントリの論理削除が可能に。
- **PTIF 生成の自動化プロセス改善**
  - ラベリング完了（Step 4: Save & Finish）時に、PTIF 生成ジョブをバックグラウンドで自動開始するよう改善。
- **ラベルのユニーク制約バリデーションの実装**
  - 同一 PDF 内でのラベル（図番号等）の重複をリアルタイムで検出し、警告を表示。
  - 重複がある場合は既存レコードへの編集リンクを表示し、データの整合性をサポート。
- **高解像度クロップ画像のダウンロード機能**
  - 公開ギャラリーに「ダウンロード」ボタンを追加。
  - 遺跡名とラベルを組み合わせたセマンティックな日本語ファイル名で保存可能。

### 🎮 操作性向上
- **クロップ保存のダブルクリック操作を導入**
  - クロップ範囲の決定（Step 3）において、選択範囲のダブルクリック（またはダブルタップ）による明示的な保存操作を導入。
  - 意図しない座標の保存を防止し、より確実な操作体験を提供。

---

## [0.2.2] - 2026-02-13

### 🎨 UI & テーマ
- **Admin Review Dashboard (`/admin/review`) を「新潟インディゴ＆ハーベストゴールド」テーマに対応**
  - 公開ギャラリーと視覚的に統一されたダークテーマ環境
  - ステータスに応じたカードボーダー（Pending: Gold, Approved: Green）
  - 高コントラストな Approve/Reject ボタン（60×60px）
  - ダークテーマに最適化された Inspector Panel とモーダル

### 🎮 操作性改善 (D-Pad)
- **Nudge コントロールを D-Pad (Directional Pad) レイアウトに刷新**
  - 3×3 CSS Grid による直感的な配置
  - ボタンサイズを 64×64px に拡大し、誤操作を防止
  - ナッジ量を 5px → 10px に変更
  - キーボードの矢印キーによる操作に対応（`phx-window-keydown`）
  - Undo ボタンを D-Pad 中央に統合

### ✂️ クロップ & レンダリング改善
- **Label 画面でのクロップ表示を SVG 方式に移行**
  - CSS スケールに依存しない、より精密なクロッププレビューを実現
- **提出プロセスの改善**
  - 保存・提出時にアイテムのステータスを自動的に `pending_review` へ更新

### 🛡️ セキュリティ & 品質
- **セキュリティ脆弱性の修正 (Sobelow)**
  - `pdf_processor`, `pipeline`, `image_controller`, `upload` におけるディレクトリトラバーサルおよび XSS リスクの低減
- **`mix review` パイプラインのパス**
  - 全チェック（Compile, Credo, Sobelow, Dialyzer）を通過

---

## [0.2.1] - 2026-02-13 (Retrospective)

### ✂️ クロップ機能の基礎改善

#### 変更

- **Cropper.js を廃止し、オリジナルの JavaScript Hook (`ImageSelection`) に移行**
  - CSS スケール（`object-fit: contain`）を考慮した正確な座標計算の実装
  - SVG オーバーレイの表示制御を JS 側に移行し、LiveView 更新時のチラつきや座標の跳びを解消
  - Harvest Gold テーマに合わせた選択範囲の視覚的フィードバックの強化

---

## [0.2.0] - 2026-02-11

### 🏛️ ランディングページ刷新 — デジタルミュージアムの入口

#### 追加

- **ランディングページ（`/`）を「新潟インディゴ＆ハーベストゴールド」テーマに全面刷新**
  - Deep Navy/Indigo (`#001f3f`) 背景 + Harvest Gold (`#d4af37`) アクセント
  - CTA ボタン「Enter the Digital Gallery」→ `/gallery` への一本道ナビゲーション
  - 最小 60×60px タッチターゲット（WM 70 認知アクセシビリティ対応）
  - ミニマリストフッターに `/lab`・`/admin` リンクを控えめ配置

#### 変更

- **ルーター構成の整理**
  - 公開スコープ（`/`, `/gallery`）と 内部スコープ（`/lab/*`）を分離
  - 将来の認証プラグ追加に備えた構造化
- **Tailwind CSS v4 `@source` ディレクティブ追加**
  - `.heex` テンプレートの自動スキャン対応

---

## [0.1.2] - 2026-02-10

### 🛡️ Admin Review Dashboard

#### 追加

- **管理者レビュー機能 (`/admin/review`)**
  - 公開前の最終品質ゲートとして機能
  - Nudge Inspector による詳細確認とクロップ微調整
  - Validation Badge による自動チェック結果表示
  - 承認 (`published`) / 差し戻し (`draft`) のステータス管理
  - Optimistic UI によるスムーズな操作体験

## [0.1.1] - 2026-02-10

### 🎨 UI テーマ更新

#### 追加

- **公開ギャラリーテーマ: 新潟インディゴ＆ハーベストゴールド**
  - Deep Sea Indigo (`#1A2C42`) 背景によるダークテーマ化
  - Harvest Gold (`#E6B422`) アクセントカラーで操作フィードバック
  - Mist Grey (`#E0E0E0`) テキストで WCAG AAA 準拠のコントラスト比 (≈ 10.4:1)
  - ギャラリー専用カード・検索バー・フィルターチップスのダークスタイル適用
  - フィルターチップの `min-height` を 48px → 60px に引き上げ (WM 70 対応)
  - Hover/Active に Gold パレットの非言語フィードバック実装
  - CSS 変数 + `.gallery-container` スコープで Lab/Admin 画面に影響なし (Zero-Regression)

---

## [0.1.0] - 2026-02-09

### 🎉 初回リリース

#### 追加

- **Manual Inspector ウィザード（全5ステップ）**
  - Step 1: PDF アップロード + 自動 PNG 変換 (pdftoppm 300 DPI)
  - Step 2: サムネイルグリッドによるページ選択
  - Step 3: Cropper.js によるマニュアルクロップ + Nudge コントロール
  - Step 4: ラベリング（キャプション・ラベル・メタデータの手入力）
  - Step 5: レビュー提出（PTIF 自動生成 + IIIF Manifest 登録）
  - 共通ウィザードコンポーネント (`wizard_components.ex`)

- **IIIF サーバー**
  - Image API v3.0 (`/iiif/image/:identifier/...`)
  - Presentation API v3.0 (`/iiif/manifest/:identifier`)
  - info.json エンドポイント
  - タイルキャッシュ機構

- **検索機能**
  - 全文検索コンテキスト (`OmniArchive.Search`)
  - 検索用 LiveView (`SearchLive`)
  - `extracted_images` への検索フィールド追加マイグレーション

- **Stage-Gate ワークフロー**
  - Lab (内部) / Gallery (公開) の分離
  - 承認ワークフロー LiveView (`ApprovalLive`)
  - ギャラリー LiveView (`GalleryLive`)
  - `extracted_images` へのステータスカラム追加マイグレーション

- **データベース**
  - PostgreSQL + JSONB メタデータ
  - `pdf_sources`, `extracted_images`, `iiif_manifests` テーブル

- **認知アクセシビリティ**
  - 最小 60×60px のタッチターゲット
  - 高コントラストカラーパレット
  - ウィザードパターンによる線形フロー
  - 即時フィードバック

- **テスト**
  - コンテキスト・スキーマ・コントローラ・LiveView のテスト
  - テスト用ファクトリ (`test/support/factory.ex`)

- **並列処理パイプライン**
  - リソース適応型並列処理 (`OmniArchive.Pipeline`)
  - CPU/メモリ自動検出・動的並列度調整 (`OmniArchive.Pipeline.ResourceMonitor`)
  - メモリガード（空きメモリ 20% 未満で並列度縮小）
  - PubSub リアルタイム進捗通知

- **品質チェック (`mix review`)**
  - Credo コードスタイル検査 (`--strict`)
  - Sobelow セキュリティ解析
  - Dialyzer 型チェック
  - PASS/FAIL サマリータスク (`mix review.summary`)

- **デプロイ**
  - マルチステージ Dockerfile (libvips + poppler-utils)
  - OTP リリースサポート
  - ヘルスチェックエンドポイント (`/api/health`)
