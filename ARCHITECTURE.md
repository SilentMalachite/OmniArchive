# Architecture / アーキテクチャ設計書

## Overview / 概要

OmniArchive is a **modular monolith** built with Elixir and Phoenix. It separates three
concerns — Ingestion, Search, and Delivery — behind clear module boundaries while keeping
the operational simplicity of a single codebase.

A **Stage-Gate model** separates the internal workspace (Lab) from the public space
(Gallery), controlling quality through an explicit approval flow.

OmniArchive は **モジュラー・モノリス** アーキテクチャを採用した Elixir/Phoenix アプリケーションです。
「取り込み (Ingestion)」「検索 (Search)」「配信 (Delivery)」を明確なモジュール境界で分離しつつ、
単一コードベースの運用効率を維持します。

**Stage-Gate モデル** により、内部作業空間 (Lab) と公開空間 (Gallery) を分離し、
承認フローを通じて品質を管理します。

---

## Why Elixir and Phoenix / なぜ Elixir/Phoenix を選んだか

Three properties of the Elixir ecosystem made it the right choice for OmniArchive:

1. **OTP concurrency model for large PDF processing** — Elixir's OTP (Open Telecom
   Platform) allows each user to get a dedicated background worker process
   (`UserWorker` / `GenServer`). Large PDFs (200+ pages) are chunked and processed
   sequentially without blocking the UI, even on a 2 GB VPS. The supervisor tree
   restarts failed processes automatically.

2. **LiveView real-time UI without a JavaScript framework** — Phoenix LiveView delivers
   real-time progress updates (chunk progress bar, status changes) over a WebSocket
   connection. No separate JavaScript framework or API layer is needed, which simplifies
   deployment and reduces the surface area for accessibility regressions.

3. **Pattern matching makes metadata validation clear** — Elixir's pattern matching lets
   the `DomainProfiles` behavior express per-field validation rules, vocabulary
   constraints, and facet labels in a way that is easy to audit. Adding a new domain
   profile (manuscripts, maps, photographs) requires only implementing a single behavior
   module or writing a YAML file.

Elixir エコシステムの以下の3つの特性が OmniArchive に適していました：

1. **OTP の並列処理モデル** — ユーザーごとに専属の `UserWorker` (GenServer) を起動し、
   大規模 PDF 処理を UI スレッドから完全に分離できます。メモリ 2GB の VPS でも OOM を回避します。
2. **LiveView によるリアルタイム UI 更新** — JavaScript フレームワークを別途導入せず、
   WebSocket を通じてリアルタイムの進捗表示・ステータス変更が可能です。
3. **パターンマッチングによる明瞭なバリデーション** — `DomainProfiles` ビヘイビアを使い、
   フィールドごとのバリデーションルール・語彙制約・ファセットラベルを簡潔に記述できます。

---

## Module Structure / モジュール構成

The modular monolith separates three top-level concerns — Ingestion, Search, and
Delivery — over a shared PostgreSQL instance. Each concern owns its context module
and has clear boundaries toward the others.

モジュラー・モノリスは「取り込み (Ingestion)」「検索 (Search)」「配信 (Delivery)」の3つの関心事を
共有の PostgreSQL 上で明確に分離します。各関心事は独自のコンテキストモジュールを持ち、
相互の境界が明示されています。

```
┌──────────────────────────────────────────────────────────────────┐
│                         OmniArchive                               │
├──────────────────┬──────────────────┬────────────────────────────┤
│  取り込みモジュール │  検索モジュール   │       配信モジュール        │
│  (Ingestion)     │  (Search)        │    (IIIF Delivery)        │
├──────────────────┼──────────────────┼────────────────────────────┤
│ • PDF アップロード │ • 全文検索 (FTS) │ • Image API v3.0          │
│ • pdftoppm 変換   │ • ファセット検索  │ • Presentation API v3.0   │
│ • 手動クロップ    │ • メタデータ検索  │ • タイルキャッシュ          │
│   (矩形・ポリゴン) │                  │                            │
│ • PTIF 生成       │                  │ • JSON-LD Manifest        │
│ • メタデータ入力  │                  │                            │
└────────┬─────────┴────────┬─────────┴──────────────┬─────────────┘
         │                  │                        │
         ▼                  ▼                        ▼
┌──────────────────────────────────────────────────────────────────┐
│                     PostgreSQL (JSONB)                            │
│  pdf_sources | extracted_images | iiif_manifests                  │
└──────────────────────────────────────────────────────────────────┘
```

### Pipeline Module / パイプラインモジュール

The Pipeline module orchestrates PDF extraction and PTIF generation in batches. The
ResourceMonitor GenServer watches CPU and memory usage and adjusts concurrency at
runtime so the host stays responsive.

Pipeline モジュールは PDF 抽出と PTIF 生成をバッチ単位でオーケストレートします。
ResourceMonitor GenServer が CPU とメモリ使用量を監視し、ホストの応答性を維持するように
並列度を実行時に調整します。

```
┌───────────────────────────────────────────────────────┐
│              並列処理パイプライン (Pipeline)              │
├──────────────────────────┬────────────────────────────┤
│  Pipeline               │  ResourceMonitor             │
│  (オーケストレーター)    │  (GenServer)                 │
├──────────────────────────┼────────────────────────────┤
│ • Task.async_stream     │ • CPU コア数検出            │
│ • PubSub 進捗通知     │ • メモリガード (20%)       │
│ • バッチ PDF 抽出      │ • 動的並列度計算          │
│ • バッチ PTIF 生成    │ • UI 用 1コア予約         │
│ • ジョブ固有一時Dir   │ • Dev: Upload Cleanup      │
│   (並行安全)           │                              │
└──────────────────────────┴────────────────────────────┘
```

> **並行安全性**: PDF 変換時にジョブごとのユニーク一時ディレクトリ
> (`omniarchive_job_{uuid}`) を使用し、`try/after` パターンで確実にクリーンアップ。
> 並行実行される複数ジョブ間でのファイル衝突を防止します。

> **libvips グローバル制約**: `Application.start/2` で libvips の並行処理パラメータを設定
> します。`concurrency_set(1)` で libvips 内部のスレッド競合を防止し、`cache_set_max(100)`
> / `cache_set_max_mem(512MB)` でキャッシュ上限を設定します。Elixir 側で Task.async_stream
> による並行処理を管理し、libvips はシングルスレッドで動作させることで OOM を防止します。

> **PDF チャンク逐次処理**: 大規模 PDF（200+ ページ）でも OOM を回避するため、
> `PdfProcessor` は PDF を 10 ページ単位のチャンクに分割し、
> `Task.async_stream(max_concurrency: 1)` で逐次 `pdftoppm` を実行します。
> `pdfinfo` でページ数を事前取得し、チャンク完了後に `Path.wildcard` で PNG を
> 収集・ソート・タイムスタンプ付きリネームします。

> **PDF カラーモード**: Upload 画面で「モノクロ（高速）」と「カラー（標準）」を選択可能です。
> カラーモードは `UserWorker.process_pdf/5` → `Pipeline` → `PdfProcessor` へと伝搬され、
> モノクロモード時は `pdftoppm` に `-gray` フラグを付与してグレースケール変換します。
> デフォルトはモノクロモードで、線画中心の資料では処理速度とファイルサイズの両面で有利です。

> **Lazy PTIFF 生成**: メタデータ編集中に毎回 PTIFF を生成すると CPU/ストレージを浪費します。
> `Ingestion.approve_and_publish/1` において、管理者が明示的に「承認」した時点でのみ
> `OmniArchive.Iiif.PtiffGenerator` を呼び出し、公開用 PTIFF を生成します。
> 線画の品質を保つため、DEFLATE 可逆圧縮を採用しています。

> **チャンク進捗ブロードキャスト**: `convert_to_images/3` に `opts` (`%{user_id: ...}`) を
> 渡すことで、チャンク完了ごとに `{:extraction_progress, current_page, total_pages}` を
> PubSub (`pdf_pipeline:{user_id}`) に配信します。Upload 画面はこの通知を受信して
> プログレスバーをリアルタイムに更新します。`user_id` が未指定の場合は安全にスキップします。

> **DB 挿入の最適化 (Bulk Insert)**: `Pipeline` での `ExtractedImage` レコード登録は、
> 個別 `Repo.insert` ループではなく `Ingestion.bulk_create_extracted_images/1`
> (`Repo.insert_all/3`) による一括挿入を使用します。DB ラウンドトリップを N 回から 1 回に
> 削減し、Ecto changeset オーバーヘッドを排除することで大規模 PDF の処理を高速化します。
> タイムスタンプ (`inserted_at` / `updated_at`) やデフォルト値 (`status`, `lock_version`)
> は `insert_all` が Ecto の auto-timestamp をバイパスするため、明示的に設定しています。

### OTP Background Processing / OTP バックグラウンド処理基盤

OTP separates heavy processing (PDF extraction, PTIF generation) from the LiveView
process, keeping the UI responsive at all times.

PDF 抽出などの重い処理を LiveView プロセスから分離し、UI のレスポンスを保証するための OTP 基盤です。

```
┌──────────────────────────────────────────────────────────────┐
│                  Application Supervision Tree                 │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  OmniArchive.DomainProfiles.YamlCache  (GenServer, 条件付き)    │
│  └── OMNI_ARCHIVE_PROFILE_YAML 設定時のみ起動                  │
│      YAML プロファイルを ETS にキャッシュ                       │
│                                                               │
│  OmniArchive.UserWorkerRegistry  (Registry)                    │
│  └── ユーザー ID → PID のマッピング                             │
│                                                               │
│  OmniArchive.UserWorkerSupervisor  (DynamicSupervisor)         │
│  └── UserWorker (GenServer) × N  ← ユーザーごとに 1 プロセス  │
│                                                               │
├──────────────────────────────────────────────────────────────┤
│                     処理フロー                                 │
│                                                               │
│  LiveView (Upload)                                            │
│    │  UserWorker.process_pdf/5 (cast, color_mode 付き)        │
│    ▼                                                          │
│  UserWorker (GenServer)                                       │
│    │  Task.start で非同期実行                                  │
│    ▼                                                          │
│  Pipeline.run_pdf_extraction/4                                │
│    │  PdfProcessor.convert_to_images/3                        │
│    │    └── チャンク完了ごとに                                  │
│    │        PubSub {:extraction_progress, current, total}     │
│    │        (トピック: pdf_pipeline:{owner_id})                │
│    │                                                          │
│    │  成功時                                                   │
│    ├── PubSub broadcast {:extraction_complete, pdf_source_id} │
│    │   (トピック: pdf_pipeline:{owner_id})                     │
│    ▼                                                          │
│  LiveView (handle_info)                                       │
│    ├── {:extraction_progress, ...} → プログレスバー更新       │
│    └── {:extraction_complete, ...} → Browse 画面へ遷移        │
└──────────────────────────────────────────────────────────────┘
```

> **ワーカー自動起動**: `UserAuth.mount_current_user` フック内で、認証済みユーザーの
> `UserWorker` を自動起動します。既に起動済み (`{:error, {:already_started, _}}`) の
> 場合は安全に無視されます。

### Domain Profiles / ドメインプロファイル

Domain profiles define metadata fields, validation rules, search facets, and UI text
as a swappable configuration. This allows different institutions to use their own
metadata schemas without changing application code.

メタデータフィールド・バリデーション・検索ファセット・UI テキストをプロファイルとして定義する仕組みです。
機関ごとの独自メタデータスキーマをアプリケーションコードを変更せずに適用できます。

```
┌──────────────────────────────────────────────────────────┐
│                  DomainProfile ビヘイビア                  │
├───────────────────────┬──────────────────────────────────┤
│  組み込みプロファイル   │  YAML プロファイル (v0.2.23 以降)  │
├───────────────────────┼──────────────────────────────────┤
│ Archaeology (デフォルト)│  YamlLoader                     │
│ GeneralArchive        │  └── YAML ファイルをパース・検証  │
│                       │  YamlCache (GenServer + ETS)      │
│                       │  └── 起動時に一度だけキャッシュ   │
│                       │  Yaml モジュール                  │
│                       │  └── YamlCache に委譲             │
└───────────────────────┴──────────────────────────────────┘
```

**有効化**: `OMNI_ARCHIVE_PROFILE_YAML=/path/to/profile.yaml` 環境変数を設定すると、`runtime.exs` が自動的に `OmniArchive.DomainProfiles.Yaml` を active profile に設定し、スーパービジョンツリーに `YamlCache` を追加します。未設定時は `Archaeology` がデフォルトとして使用されます。

**予約キー保護**: アクティブな YAML プロファイルのフィールドキーは `CustomMetadataField` の DB カスタムフィールドとして登録できません（重複防止）。

---

### Stage-Gate Flow / Stage-Gate フロー

The Stage-Gate flow moves items from the internal Lab workspace through an explicit
admin approval step before they become visible in the public Gallery. Rejected items
return to the workspace with a reviewer message and can be resubmitted.

Stage-Gate フローは、内部作業空間 Lab で作成されたアイテムを、管理者による明示的な承認ゲートを
経由してから公開 Gallery に表示する仕組みです。差し戻されたアイテムは管理者メッセージとともに
作業空間に戻り、修正後に再提出できます。

```
Lab (内部 — 全5ステップ)     承認ゲート                  Gallery (公開)
─────────────────────        ──────────                  ──────────────
Upload → Browse →           ApprovalLive /              GalleryLive
Crop → Label → Finalize    ReviewLive (/admin)         (published のみ表示)
(status: draft)             (pending_review →
                            published / rejected)
SearchLive               ステータス変更          IIIF API 配信
(Lab 内検索)          (pending_review →
                        published / rejected / deleted)

                         rejected → 再提出 →
                         pending_review (Fix & Resubmit)
```

### Project Workflow Status / プロジェクト ワークフローステータス

Project-level workflow status (`PdfSource`) is tracked independently from individual
image status (`extracted_images.status`).

プロジェクト（`PdfSource`）単位で作業進捗を管理するワークフローステータスを導入しています。
画像個別のステータス（`draft` / `pending_review` / `published` 等）とは独立に管理されます。

```
 wip（作業中）──→ pending_review（審査待ち）──→ approved（承認済み）
   ↑                    │
   │                    ▼
   └──────── returned（差し戻し）
             return_message に理由を記録
```

| 遷移 | 関数 | 動作 |
|:---|:---|:---|
| 提出 | `submit_project/1` | `wip` / `returned` → `pending_review`。`return_message` をクリア |
| 差し戻し | `return_project/2` | `pending_review` → `returned`。管理者メッセージを保存 |
| 承認 | `approve_project/1` | `pending_review` → `approved` |

> **Write-on-Action ポリシー**: Browse（Step 2）でページを選択しても DB にレコードは
> 作成されません。ExtractedImage レコードは Crop（Step 3）でユーザーが明示的に
> クロップ範囲を保存した時に初めて作成されます。これにより空のゴーストレコードの
> 発生を防止します。

> **ギャラリーモーダル**: 公開ギャラリーではカードクリックにより、IIIF 対応の
> OpenSeadragon を使用したシームレスな拡大表示モーダルを表示します
> （PTIFF 生成前の場合は SVG `viewBox` ベースのフォールバック表示）。
> `#osd-viewer` への専用 CSS 適用により確実なインタラクション（マウスイベント等）を実現しています。
> 閉じる操作は `Esc` キーまたは背景クリックに統一し、閉じるボタンは配置しません。
> カードのホバーエフェクトは `border-color` 変更のみに簡素化し、
> `will-change: transform` で GPU ヒントを付与することでちらつきを防止しています。

---

## Data Flow / データフロー

Data flows through three stages — Ingestion, Approval, and Delivery — each with
clear inputs, outputs, and storage touchpoints.

データは「取り込み (Ingestion)」「承認 (Approval)」「配信 (Delivery)」の 3 段階を通過します。
各段階には明確な入出力と永続化ポイントがあります。

### Ingestion Pipeline / 取り込みパイプライン (Ingestion)

Uploaded PDFs are chunked, converted to PNG thumbnails, cropped manually, labeled
with metadata, and finally submitted for review. ExtractedImage records are created
only at the crop step (Write-on-Action) to avoid ghost rows.

アップロード済み PDF はチャンク分割・PNG サムネイル化・手動クロップ・メタデータ入力を経て
レビュー提出されます。ExtractedImage レコードはクロップ時にのみ作成され
（Write-on-Action）、空レコードの発生を防ぎます。

```
PDF ファイル
    │  Step 1: アップロード (/lab)
    ▼
[pdfinfo] ──── ページ数を取得
    │
    ▼
[pdftoppm] ──── 10 ページ単位でチャンク分割 → 300 DPI PNG 逐次生成
    │
    ▼
サムネイルグリッド (/lab/browse/:pdf_source_id)
    │  Step 2: ユーザーがページ選択（レコード作成なし — Write-on-Action）
    ▼
ImageSelection Hook ──── ポリゴン手動クロップ (/lab/crop/:pdf_source_id/:page_number)
    │  Step 3: クリックで頂点追加 → ダブルクリック（または始点クリック/Enter）で
    │          多角形を閉じて保存。★ ここで初めて ExtractedImage レコードを INSERT。
    │          D-Pad でポリゴン全体を微調整可能。
    ▼
メタデータ入力フォーム (/lab/label/:image_id)
    │  Step 4: caption, label, および active profile で定義された metadata を手入力。自動ラベリング保存。
    │          geometry nil の場合は保存をブロック。
    ▼
レビュー提出ステータスの確認 (/lab/finalize/:id)
    │  Step 5: 入力内容の最終確認とレビュー依頼。
    ▼
[管理者承認ゲート] ──── /admin/review
    │  Admin が「承認」をクリック。
    ▼
[OmniArchive.Iiif.PtiffGenerator] ── クロップ画像 → PTIF 生成 (DEFLATE圧縮)
    │  ここで初めて IIIF 公開用の実ファイルが生成される (Lazy Generation)。
    ▼
PostgreSQL ──── status: published
                Gallery に公開
```

### Approval Pipeline / 承認パイプライン (Stage-Gate)

Items move from draft to published only after a reviewer clicks Approve in
`/admin/review`. PTIFs for IIIF delivery are generated lazily at this step.

アイテムは `/admin/review` で管理者が承認した時点ではじめて `published` に遷移します。
IIIF 配信用の PTIF はこの段階で遅延生成されます。

```
Lab (draft) → 承認申請 (pending_review) → 承認 (published) → Gallery
                                         (Admin: /admin/review)
                                         ↗
                 差し戻し → (rejected) → 修正・再提出 → (pending_review)
```

### Delivery Pipeline / 配信パイプライン (Delivery)

IIIF clients such as Mirador and Universal Viewer retrieve Manifests and image tiles
directly from OmniArchive's endpoints. Tiles are cached on first request.

```
IIIF クライアント (Mirador, Universal Viewer 等)
    │
    ├── /iiif/manifest/{id} ──── 個別画像 Manifest (published のみ)
    │
    ├── /iiif/presentation/{source_id}/manifest
    │       ──── PdfSource 単位 Manifest (published 画像を Canvas に集約)
    │
    ▼
/iiif/image/{id}/{region}/{size}/{rotation}/{quality}
    │
    ├── キャッシュあり → priv/static/iiif_cache から配信
    │
    └── キャッシュなし → [vix] PTIF からタイル生成
                              → キャッシュ保存
                              → レスポンス返却
```

---

## Data Schema / データスキーマ

OmniArchive stores bibliographic data in PostgreSQL with JSONB columns for
flexible per-profile metadata. Soft delete and optimistic locking protect data
integrity across concurrent edits.

OmniArchive は書誌データを PostgreSQL に保存し、プロファイルごとに柔軟な
メタデータを JSONB カラムで扱います。ソフトデリートと楽観的ロックにより、
同時編集時のデータ整合性を確保します。

### Entity-Relationship Diagram / Entity-Relationship 図

```
┌──────────────────┐  1:N  ┌────────────────────────┐    1:1    ┌────────────────┐
│   pdf_sources    │ ─────>│   extracted_images     │ ────────> │ iiif_manifests │
├──────────────────┤       ├────────────────────────┤           ├────────────────┤
│ id               │       │ id                     │           │ id             │
│ user_id (FK)     │       │ pdf_source_id(FK)      │           │ extracted_     │
│ filename         │       │ page_number            │           │   image_id(FK) │
│ page_count       │       │ image_path             │           │ identifier     │
│ status           │       │ geometry (JSONB)       │           │ metadata(JSONB)│
│ workflow_status  │       │ caption                │           │ inserted_at    │
│ return_message   │       │ label                  │           │ updated_at     │
│ deleted_at       │       │ ptif_path              │           └────────────────┘
│ inserted_at      │       │ status                 │
│ updated_at       │       │ review_comment         │
└──────────────────┘       │ lock_version           │
                           │ owner_id(FK → users)   │
┌──────────────┐           │ worker_id(FK → users)  │
│    users     │           │ metadata (JSONB)       │
├──────────────┤           │ site (legacy)          │
│ id           │ ◄─────────│ period (legacy)        │
│ email        │   N:1     │ artifact_type (legacy) │
│ hashed_pw    │           │ inserted_at            │
│ confirmed_at │           └────────────────────────┘
│ inserted_at  │
│ updated_at   │
└──────────────┘
```

### `extracted_images.status` Lifecycle / ライフサイクル

| Value / 値 | Description / 説明 |
|:---|:---|
| `draft` | 初期状態（Lab で作成直後） |
| `pending_review` | レビュー待ち（承認申請済み） |
| `rejected` | 差し戻し（要修正。`review_comment` に理由を記録） |
| `published` | 公開中（承認済み） |
| `deleted` | 削除済み（論理削除） |

### `pdf_sources.workflow_status` Lifecycle / ライフサイクル

| Value / 値 | Description / 説明 |
|:---|:---|
| `wip` | 作業中（初期状態） |
| `pending_review` | 作業完了/審査待ち（一般ユーザーが提出済み） |
| `returned` | 差し戻し（`return_message` に管理者メッセージを記録） |
| `approved` | 承認済み |

### JSONB Column Details / JSONB カラムの詳細

**`extracted_images.geometry`** — crop coordinates / クロップ座標

矩形形式（旧データ・後方互換）：
```json
{
  "x": 150,
  "y": 200,
  "width": 800,
  "height": 600
}
```

ポリゴン形式（v0.2.22 以降）：
```json
{
  "points": [
    {"x": 100, "y": 150},
    {"x": 500, "y": 120},
    {"x": 520, "y": 600},
    {"x": 80,  "y": 580}
  ]
}
```

> **ポリゴンクロップの処理**: `ImageProcessor` は `points` 配列を検出すると、
> バウンディングボックスで `extract_area` → SVG マスク生成 → `ifthenelse` 白背景合成
> の 4 段階パイプラインで処理します。ポリゴン外は純白 (255,255,255) で塗りつぶされ、
> JPEG 互換の 3バンド RGB 画像として出力されます（アルファチャンネル不要）。
> プレビュー表示では SVG `clipPath` + `<polygon>` によるマスキングを使用します。

**`iiif_manifests.metadata`** — IIIF metadata (multilingual) / IIIF メタデータ (多言語)

```json
{
  "label": {
    "en": ["Figure 3: Pottery excavation"],
    "ja": ["第3図: 土器出土状況"]
  },
  "summary": {
    "en": ["Catalog figure"],
    "ja": ["資料の図版"]
  }
}
```

### Soft Delete and Deletion Protection / ソフトデリート & 削除防止

`PdfSource` uses soft delete to allow recovery from accidental deletion.
Published projects are protected from deletion.

`PdfSource` はソフトデリート方式を採用し、誤削除からの復元を可能にしています。

| Operation / 操作 | Function / 関数 | Behavior / 動作 |
|:---|:---|:---|
| ゴミ箱に移動 | `soft_delete_pdf_source/1` | `deleted_at` を現在時刻に設定。物理ファイルは保持 |
| 復元 | `restore_pdf_source/1` | `deleted_at` を `nil` に戻す |
| 完全削除 | `hard_delete_pdf_source/1` | 物理ファイル・DB レコードをトランザクション内で完全削除 |

> **公開済みプロジェクトの保護**: `is_published?/1` により、公開済み画像を含むプロジェクトの
> ソフトデリートを拒否します（`{:error, :published_project}`）。Lab UI ではロックアイコンと
> 無効化ボタンで視覚的に保護状態を表示します。

### Data Integrity and Validation / データ整合性とバリデーション

Validation runs at both the application layer (profile-driven rules) and the
database layer (unique indexes, optimistic locking). This two-tier approach
guarantees consistent bibliographic data even under concurrent access.

データの品質を保証するため、アプリケーションレベル（プロファイル定義ルール）と
データベースレベル（ユニーク制約・楽観的ロック）の両方で厳格なバリデーションを実施しています。

1.  **厳格な入力バリデーション**:
    *   **ラベル形式**: active profile の validation 定義に従って強制。
    *   **メタデータ検証**: profile ごとの文字数・形式・語彙ルールを `DomainProfiles.*` から適用。
2.  **ユニーク制約**:
    *   現在は `[:site, :label]` の複合ユニークインデックスを維持し、互換性レイヤー経由で重複を防止します。
3.  **ファイルバージョニング**:
    *   アップロードされたファイル名には `filename-{timestamp}.ext` 形式でタイムスタンプを付与。
    *   ブラウザキャッシュの衝突（ゴースト画像問題）を防止し、同名ファイルの安全な再アップロードを保証します。
4.  **楽観的ロック (Optimistic Locking)**:
    *   `extracted_images` テーブルに `lock_version` カラムを追加し、Ecto の `optimistic_lock` 機能を利用。
    *   複数ユーザー（またはタブ）による同時編集時の「後勝ち」更新を防止し、データの整合性を維持します。
    *   競合検出時は `Ecto.StaleEntryError` が発生し、UI 側で適切なエラーメッセージを表示します。
5.  **入力値の長さ制限**:
    *   `caption` と active profile で定義された metadata に対し、profile ベースの文字数制限を適用。
    *   フロントエンドの制限に依存せず、サーバーサイドでのバリデーションエラーを日本語で明示し、意図しないデータ投入やXSSをサーバーレベルで阻止します。

---

## Routing / ルーティング構成

Routes are grouped into three scopes: public (IIIF endpoints and the Gallery),
authenticated (Lab and Admin), and authentication flow routes. Authentication
enforcement happens in the Phoenix router via the `require_authenticated_user`
plug.

ルートは「公開スコープ（IIIF エンドポイント・Gallery）」「認証必須スコープ（Lab・Admin）」
「認証フロー」の 3 系統に分類されます。認証は Phoenix ルーターで
`require_authenticated_user` プラグにより強制されます。

### Public Scope (no authentication required) / 公開スコープ（認証不要）

| Path / パス | Module / モジュール | Description / 説明 |
|:---|:---|:---|
| `/` | `PageController` | トップページ |
| `/gallery` | `GalleryLive` | 公開ギャラリー (Gallery) |
| `/iiif/image/:id/...` | `ImageController` | IIIF Image API v3.0 |
| `/iiif/manifest/:id` | `ManifestController` | IIIF Presentation API v3.0 (個別画像) |
| `/iiif/presentation/:source_id/manifest` | `PresentationController` | IIIF Presentation API v3.0 (PdfSource 単位) |
| `/api/health` | `HealthController` | ヘルスチェック |

### Authenticated Scope / 認証必須スコープ (`require_authenticated_user`)

| Path / パス | Module / モジュール | Description / 説明 |
|:---|:---|:---|
| `/lab` | `LabLive.Index` | Lab: プロジェクト一覧 |
| `/lab/projects/:id` | `LabLive.Show` | Lab: プロジェクト詳細（画像グリッド） |
| `/lab/upload` | `InspectorLive.Upload` | Lab: Step 1 — PDF アップロード |
| `/lab/browse/:pdf_source_id` | `InspectorLive.Browse` | Lab: Step 2 — ページ選択 |
| `/lab/crop/:pdf_source_id/:page_number` | `InspectorLive.Crop` | Lab: Step 3 — クロップ (Write-on-Action) |
| `/lab/label/:image_id` | `InspectorLive.Label` | Lab: Step 4 — ラベリング |
| `/lab/finalize/:image_id` | `InspectorLive.Finalize` | Lab: Step 5 — レビュー提出 |
| `/lab/search` | `SearchLive` | Lab: 検索 |
| `/lab/approval` | `ApprovalLive` | Lab: 承認管理 |
| `/admin` | `PageController.redirect_admin` | → `/admin/review` へリダイレクト |
| `/admin/dashboard` | `DashboardLive` | Admin: 管理ダッシュボード |
| `/admin/users` | `UserManagementLive` | Admin: ユーザー管理 |
| `/admin/review` | `ReviewLive` | Admin: 最終承認 (Review) |
| `/admin/trash` | `AdminTrashLive.Index` | Admin: ゴミ箱（ソフトデリート管理） |
| `/users/settings` | `UserSettingsController` | ユーザー設定 |

### Authentication Routes / 認証ルート

| Path / パス | Module / モジュール | Description / 説明 |
|:---|:---|:---|
| `/users/log-in` | `UserSessionController` | ログイン |
| `/users/register` | `UserRegistrationController` | ユーザー登録 |
| `/users/log-out` | `UserSessionController` | ログアウト |

---

## IIIF API Specification / IIIF API 仕様

OmniArchive exposes both the IIIF Image API v3.0 and the IIIF Presentation API v3.0.
Manifests are served as JSON-LD and are loadable directly by standard viewers such as
Mirador 3, Universal Viewer, and Clover IIIF. See [IIIF_SPEC.md](IIIF_SPEC.md) for the
authoritative endpoint reference.

OmniArchive は IIIF Image API v3.0 と IIIF Presentation API v3.0 の両方を公開します。
Manifest は JSON-LD 形式で返却され、Mirador 3・Universal Viewer・Clover IIIF などの
標準ビューアから直接読み込めます。エンドポイントの正式な仕様は
[IIIF_SPEC.md](IIIF_SPEC.md) を参照してください。

### Image API v3.0

The Image API delivers image regions, sizes, rotations, and formats on demand from
source PTIF files.

Image API は PTIF ファイルを元に領域・サイズ・回転・フォーマットをオンデマンドで配信します。

| Parameter / パラメータ | Description / 説明 | Example / 例 |
|:---|:---|:---|
| `identifier` | 画像の一意識別子 | `img-42-12345` |
| `region` | 切り出し領域 | `full`, `0,0,500,500` |
| `size` | 出力サイズ | `max`, `800,` |
| `rotation` | 回転角度 | `0`, `90`, `180`, `270` |
| `quality` | 画質 | `default`, `color`, `gray` |
| `format` | 出力フォーマット (拡張子) | `jpg`, `png`, `webp` |

**info.json response example / info.json レスポンス例:**

```json
{
  "@context": "http://iiif.io/api/image/3/context.json",
  "id": "https://example.com/iiif/image/img-42-12345",
  "type": "ImageService3",
  "protocol": "http://iiif.io/api/image",
  "width": 4000,
  "height": 3000,
  "profile": "level1"
}
```

### Presentation API v3.0

OmniArchive returns JSON-LD Manifests that conform to the IIIF Presentation API v3.0
specification. The Manifest structure includes Canvas, AnnotationPage, and Annotation
hierarchies, making it directly loadable in Mirador 3 and Universal Viewer.

IIIF 3.0 仕様に準拠した JSON-LD Manifest を返却します。
Canvas、AnnotationPage、Annotation の階層構造を含みます。

**2つのエンドポイント:**

| Endpoint / エンドポイント | Description / 説明 |
|:---|:---|
| `GET /iiif/manifest/:identifier` | 個別画像の Manifest（`iiif_manifests` テーブル経由） |
| `GET /iiif/presentation/:source_id/manifest` | PdfSource 単位の Manifest（published 画像を Canvas に集約） |

PdfSource 単位の Manifest では、Canvas のサイズは `geometry` の `width`/`height` から取得します（フォールバック: 1000×1000）。

---

## Authentication Architecture / 認証アーキテクチャ

Authentication uses session cookies with bcrypt-hashed passwords, generated by
`phx.gen.auth`. Role-based access control (RBAC) and per-user data scoping
isolate each user's projects.

認証は `phx.gen.auth` が生成するセッション Cookie と bcrypt パスワードハッシュを
使用します。ロールベースアクセス制御 (RBAC) とユーザー単位のデータスコーピングにより、
プロジェクトはユーザーごとに分離されます。

### Overview / 概要

OmniArchive uses session-based authentication provided by `phx.gen.auth` with bcrypt
password hashing. Role-based access control (RBAC) separates `admin` and `user`
capabilities.

`phx.gen.auth` (bcrypt) によるセッションベース認証を採用しています。

```
┌───────────────────────────────────────────────────────────────┐
│                    認証フロー                                    │
├───────────────────────────────────────────────────────────────┤
│                                                               │
│  [未認証] ─── /users/log-in ──┐                               │
│  [未認証] ─── /users/register ─┤                              │
│                                ▼                              │
│                          UserToken 発行                        │
│                          セッション Cookie 設定                │
│                                │                              │
│                                ▼                              │
│  fetch_current_scope_for_user プラグ                           │
│  (browser パイプライン — 全リクエスト)                          │
│         │                                                     │
│         ├── @current_scope.user あり → Lab/Admin アクセス可    │
│         └── @current_scope.user なし → /users/log-in へ       │
│                                        リダイレクト            │
└───────────────────────────────────────────────────────────────┘
```

### Key Components / 主要コンポーネント

| Component / コンポーネント | Path / パス | Role / 役割 |
|:---|:---|:---|
| `Accounts` | `lib/omni_archive/accounts.ex` | ユーザー登録・認証・トークン管理のコンテキスト |
| `User` | `lib/omni_archive/accounts/user.ex` | ユーザースキーマ（email, hashed_password） |
| `UserToken` | `lib/omni_archive/accounts/user_token.ex` | セッション・メール確認トークン |
| `UserAuth` | `lib/omni_archive_web/user_auth.ex` | 認証プラグ群 |
| `Scope` | `lib/omni_archive/accounts/scope.ex` | 認証スコープ（`@current_scope`） |

### Global Navigation Bar / グローバルナビゲーションバー

`root.html.heex` にアプリ共通のナビバーを配置。ログイン状態に応じて表示を動的に切り替えます。

| State / 状態 | Display / 表示内容 |
|:---|:---|
| ログイン済み | メールアドレス、設定リンク、ログアウト |
| 未ログイン | 登録リンク、ログインボタン |

### Ownership and Data Isolation / 所有権管理 (User Scoping) とデータ隔離

`PdfSource` に `user_id`（所有者）を追加し、マルチユーザー環境におけるデータ隔離を実現しています。
`Ingestion` コンテキストでの情報フェッチや変更処理はすべて `user_id` によるスコープが適用されており、以下のルールでアクセス制御されます。

- **Admin ロール**: 全ユーザーの `PdfSource` にアクセス可能。ダッシュボードや `/admin/review` での全件管理。
- **User ロール**: 自身が作成（アップロード）した `PdfSource` およびそれに紐づく `ExtractedImage` のみアクセス・編集可能。

他ユーザーのデータアクセス試行に対しては `Ecto.NoResultsError` を発行し、404 エラーページへフォールバックさせて不正操作を防止します。

### Owner/Worker Model / 所有者/作業者モデル (ExtractedImage)

`ExtractedImage` にも個別の `owner_id`（アップロード者）と `worker_id`（作業者）の外部キーを持たせています。
現在はこの所有権モデルと `PdfSource.user_id` の二段構えで、将来的なマルチテナントや細かなタスク割り当て基盤としての拡張性を持たせています。

---

## Frontend Architecture / フロントエンドアーキテクチャ

The frontend is built on Phoenix LiveView, with small JavaScript hooks only where
direct DOM manipulation is unavoidable (for example, the polygon crop tool). Gallery
and Lab have dedicated CSS themes, both scoped to their own container classes.

フロントエンドは Phoenix LiveView を中心に構成し、ポリゴンクロップなど DOM 直接操作が
必要な箇所にのみ小さな JavaScript Hook を配置しています。Gallery と Lab はそれぞれ専用の
CSS テーマを持ち、コンテナクラスに局所化されています。

### LiveView + JS Hook Integration / LiveView + JS Hook 統合

```
LiveView (Elixir)              JS Hook (JavaScript)
────────────────               ──────────────────────
  ↓ push_event                   ↓ Hook インストール (ImageSelection)
  "nudge_crop"  ─────────────>  setData() で位置調整
                                   ↓ cropend イベント
  handle_event  <─────────────  pushEvent("update_crop_data")
  "update_crop_data"           getData(true) を送信
```

### Gallery UI Architecture / ギャラリー UI アーキテクチャ

*   **Masonry Layout**: CSS Multi-column (`columns-xs`, `break-inside-avoid`) を採用し、Pinterest 風の不規則なグリッドレイアウトを実現。
*   **Lazy Creation**: `Browse` 画面でのページ選択時は DB レコードを作成せず（Write-on-Action）、`Crop` 画面での明示的な保存操作をトリガーとすることで、ゴーストレコードの発生を抑制します。

### Cognitive Accessibility Design Principles / 認知アクセシビリティの設計原則

1. **最小認知負荷**: 一画面で一つのタスクのみ
2. **大きなタッチターゲット**: 全ボタン最小 60×60px
3. **明確なフィードバック**: 全操作に視覚的確認
4. **破壊的操作の保護**: 確認ダイアログ必須
5. **線形ナビゲーション**: 前後のみの移動（ジャンプ不可）

### Gallery Theme / ギャラリー & 管理画面テーマ: 新潟インディゴ＆ハーベストゴールド

公開ギャラリー (`/gallery`) および 管理者レビュー画面 (`/admin/review`) には専用のダークテーマを適用しています。
CSS 変数で `.gallery-container` または `.admin-review-container` スコープに適用し、Lab 画面の基本 UI に影響を与えないように設計されています。

### Lab Project Management UI / Lab プロジェクト管理 UI

Lab のプロジェクト一覧（`/lab`）・詳細（`/lab/projects/:id`）には専用の `lab.css` を適用。
`.lab-container` スコープでカードグリッド・ステータスバッジ・画像グリッド等のスタイルを定義し、
Harvest Gold アクセントカラーによるホバーエフェクトとモバイルレスポンシブ対応を実装しています。

| Role / 役割 | Variable / 変数名 | HEX | Usage / 用途 |
|:---|:---|:---|:---|
| Base Layer | `--gallery-bg` | `#1A2C42` | ギャラリー背景 |
| Accent | `--gallery-accent` | `#E6B422` | ボタン、アクティブボーダー、ホバー |
| Typography | `--gallery-text` | `#E0E0E0` | 本文テキスト (コントラスト比 ≈ 10.4:1) |
| Surface | `--gallery-surface` | `#243B55` | カード背景 |
| Muted | `--gallery-text-muted` | `#A0AEC0` | 補助テキスト、メタ情報 |

---

## Quality Pipeline / 品質チェックパイプライン

A single `mix review` command runs compile checks, Credo style analysis, Sobelow
security analysis, and Dialyzer type checking. The pipeline stops on the first
failure, and a summary step confirms that all checks passed.

`mix review` コマンドで以下を4ステップで逐次実行します：

```
① mix compile --warnings-as-errors    → コンパイル警告ゼロ
② mix credo --strict                  → コードスタイル検査
③ mix sobelow --config                → セキュリティ解析
④ mix dialyzer                        → 型チェック
⑤ mix review.summary                  → PASS/FAIL サマリー
```

各ステップは失敗時に即座に停止し、サマリータスクが実行されることが全チェック通過を意味します。

### GitHub Actions CI Pipeline / GitHub Actions CI パイプライン

`push` (main) / `pull_request` を トリガーとした自動 CI を `.github/workflows/ci.yml` で定義しています。

```
① actions/checkout            → コードチェックアウト
② erlef/setup-beam            → Elixir 1.18.x / OTP 27 セットアップ
③ actions/cache               → deps & _build キャッシュ (mix.lock ハッシュキー)
④ mix deps.get                → 依存関係インストール
⑤ mix compile --warnings-as-errors → 厳格コンパイル
⑥ mix format --check-formatted     → フォーマットチェック
⑦ mix test                         → ExUnit テスト (PostgreSQL 15 サービスコンテナ)
```

> **サービスコンテナ**: PostgreSQL 15 をヘルスチェック付きで起動し、`config/test.exs` の
> `DB_USERNAME` / `DB_PASSWORD` / `DB_HOST` 環境変数経由で接続します。

### Configuration Files / 設定ファイル

| File / ファイル | Role / 役割 |
|:---|:---|
| `.credo.exs` | コードスタイルルール・ノイズ抑制 |
| `.sobelow-conf` | セキュリティチェック設定・除外ルール |
| `.dialyzer_ignore.exs` | 既知の型警告除外 |
