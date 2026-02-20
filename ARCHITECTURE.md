# アーキテクチャ設計書

## 概要

OmniArchive は **モジュラー・モノリス** アーキテクチャを採用した Elixir/Phoenix アプリケーションです。
「取り込み (Ingestion)」「検索 (Search)」「配信 (Delivery)」を明確なモジュール境界で分離しつつ、
単一コードベースの運用効率を維持します。

**Stage-Gate モデル** により、内部作業空間 (Lab) と公開空間 (Gallery) を分離し、
承認フローを通じて品質を管理します。

---

## モジュール構成

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

### パイプラインモジュール

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
> (`alchemiiif_job_{uuid}`) を使用し、`try/after` パターンで確実にクリーンアップ。
> 並行実行される複数ジョブ間でのファイル衝突を防止します。

### Stage-Gate フロー

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

### プロジェクト ワークフローステータス

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

> **ギャラリーモーダル**: 公開ギャラリーではカードクリックにより SVG `viewBox`
> ベースの拡大表示モーダルを表示します。閉じる操作は `Esc` キーまたは背景クリックに
> 統一し、閉じるボタンは配置しません。カードのホバーエフェクトは `border-color`
> 変更のみに簡素化し、`will-change: transform` で GPU ヒントを付与することで
> ちらつきを防止しています。

---

## データフロー

### 取り込みパイプライン (Ingestion)

```
PDF ファイル
    │  Step 1: アップロード (/lab)
    ▼
[pdftoppm] ──── 300 DPI PNG 生成
    │
    ▼
サムネイルグリッド (/lab/browse/:pdf_source_id)
    │  Step 2: ユーザーがページ選択（レコード作成なし — Write-on-Action）
    ▼
ImageSelection Hook ──── D-Pad による手動クロップ (/lab/crop/:pdf_source_id/:page_number)
    │  Step 3: 図版の範囲を指定。**ダブルクリック**で確定・保存。
    │          ★ ここで初めて ExtractedImage レコードを INSERT。
    ▼
メタデータ入力フォーム (/lab/label/:image_id)
    │  Step 4: caption, label, site, period, artifact_type を手入力。自動ラベリング保存。
    │          Save & Finish 時に PTIF 生成ジョブを自動 dispatch。
    │          geometry nil の場合は保存をブロック。
    ▼
[vix/libvips] ── クロップ画像 → PTIF 生成 (バックグラウンド)
    │  Step 5: 提出ステータスの確認 (/lab/finalize/:id)
    ▼
PostgreSQL ──── geometry(JSONB) + metadata 保存
                IIIF Manifest レコード登録
                status: draft
```

### 承認パイプライン (Stage-Gate)

```
Lab (draft) → 承認申請 (pending_review) → 承認 (published) → Gallery
                                         (Admin: /admin/review)
                                         ↗
                 差し戻し → (rejected) → 修正・再提出 → (pending_review)
```

### 配信パイプライン (Delivery)

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

## データスキーマ

### Entity-Relationship 図

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
│    users     │           │ site                   │
├──────────────┤           │ period                 │
│ id           │ ◄─────────│ artifact_type          │
│ email        │   N:1     │ inserted_at            │
│ hashed_pw    │           │ updated_at             │
│ confirmed_at │           └────────────────────────┘
│ inserted_at  │
│ updated_at   │
└──────────────┘
```

### `extracted_images.status` のライフサイクル

| 値 | 説明 |
|:---|:---|
| `draft` | 初期状態（Lab で作成直後） |
| `pending_review` | レビュー待ち（承認申請済み） |
| `rejected` | 差し戻し（要修正。`review_comment` に理由を記録） |
| `published` | 公開中（承認済み） |
| `deleted` | 削除済み（論理削除） |

### `pdf_sources.workflow_status` のライフサイクル

| 値 | 説明 |
|:---|:---|
| `wip` | 作業中（初期状態） |
| `pending_review` | 作業完了/審査待ち（一般ユーザーが提出済み） |
| `returned` | 差し戻し（`return_message` に管理者メッセージを記録） |
| `approved` | 承認済み |

### JSONB カラムの詳細

**`extracted_images.geometry`** — クロップ座標

```json
{
  "x": 150,
  "y": 200,
  "width": 800,
  "height": 600
}
```

**`iiif_manifests.metadata`** — IIIF メタデータ (多言語)

```json
{
  "label": {
    "en": ["Figure 3: Pottery excavation"],
    "ja": ["第3図: 土器出土状況"]
  },
  "summary": {
    "en": ["Archaeological report figure"],
    "ja": ["資料の図版"]
  }
}
```

### ソフトデリート & 削除防止

`PdfSource` はソフトデリート方式を採用し、誤削除からの復元を可能にしています。

| 操作 | 関数 | 動作 |
|:---|:---|:---|
| ゴミ箱に移動 | `soft_delete_pdf_source/1` | `deleted_at` を現在時刻に設定。物理ファイルは保持 |
| 復元 | `restore_pdf_source/1` | `deleted_at` を `nil` に戻す |
| 完全削除 | `hard_delete_pdf_source/1` | 物理ファイル・DB レコードをトランザクション内で完全削除 |

> **公開済みプロジェクトの保護**: `is_published?/1` により、公開済み画像を含むプロジェクトの
> ソフトデリートを拒否します（`{:error, :published_project}`）。Lab UI ではロックアイコンと
> 無効化ボタンで視覚的に保護状態を表示します。

### データ整合性とバリデーション

データの品質を保証するため、アプリケーションレベルおよびデータベースレベルで厳格なバリデーションを実施しています。

1.  **厳格な入力バリデーション**:
    *   **ラベル形式**: `fig-番号-番号` 形式（例: `fig-1-1`）を強制。
    *   **自治体名チェック**: `site`（遺跡名）には必ず市町村名（「市」「町」「村」）を含める必要があります。
2.  **ユニーク制約**:
    *   `[:site, :label]` の複合ユニークインデックスにより、同一遺跡内でのラベル重複をデータベースレベルで阻止します。
3.  **ファイルバージョニング**:
    *   アップロードされたファイル名には `filename-{timestamp}.ext` 形式でタイムスタンプを付与。
    *   ブラウザキャッシュの衝突（ゴースト画像問題）を防止し、同名ファイルの安全な再アップロードを保証します。
4.  **楽観的ロック (Optimistic Locking)**:
    *   `extracted_images` テーブルに `lock_version` カラムを追加し、Ecto の `optimistic_lock` 機能を利用。
    *   複数ユーザー（またはタブ）による同時編集時の「後勝ち」更新を防止し、データの整合性を維持します。
    *   競合検出時は `Ecto.StaleEntryError` が発生し、UI 側で適切なエラーメッセージを表示します。


---

## ルーティング構成

### 公開スコープ（認証不要）

| パス | モジュール | 説明 |
|:---|:---|:---|
| `/` | `PageController` | トップページ |
| `/gallery` | `GalleryLive` | 公開ギャラリー (Gallery) |
| `/iiif/image/:id/...` | `ImageController` | IIIF Image API v3.0 |
| `/iiif/manifest/:id` | `ManifestController` | IIIF Presentation API v3.0 (個別画像) |
| `/iiif/presentation/:source_id/manifest` | `PresentationController` | IIIF Presentation API v3.0 (PdfSource 単位) |
| `/api/health` | `HealthController` | ヘルスチェック |

### 認証必須スコープ (`require_authenticated_user`)

| パス | モジュール | 説明 |
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

### 認証ルート

| パス | モジュール | 説明 |
|:---|:---|:---|
| `/users/log-in` | `UserSessionController` | ログイン |
| `/users/register` | `UserRegistrationController` | ユーザー登録 |
| `/users/log-out` | `UserSessionController` | ログアウト |

---

## IIIF API 仕様

### Image API v3.0

| パラメータ | 説明 | 例 |
|:---|:---|:---|
| `identifier` | 画像の一意識別子 | `img-42-12345` |
| `region` | 切り出し領域 | `full`, `0,0,500,500` |
| `size` | 出力サイズ | `max`, `800,` |
| `rotation` | 回転角度 | `0`, `90`, `180`, `270` |
| `quality` | 画質 | `default`, `color`, `gray` |
| `format` | 出力フォーマット (拡張子) | `jpg`, `png`, `webp` |

**info.json レスポンス例:**

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

IIIF 3.0 仕様に準拠した JSON-LD Manifest を返却します。
Canvas、AnnotationPage、Annotation の階層構造を含みます。

**2つのエンドポイント:**

| エンドポイント | 説明 |
|:---|:---|
| `GET /iiif/manifest/:identifier` | 個別画像の Manifest（`iiif_manifests` テーブル経由） |
| `GET /iiif/presentation/:source_id/manifest` | PdfSource 単位の Manifest（published 画像を Canvas に集約） |

PdfSource 単位の Manifest では、Canvas のサイズは `geometry` の `width`/`height` から取得します（フォールバック: 1000×1000）。

---

## 認証アーキテクチャ

### 概要

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

### 主要コンポーネント

| コンポーネント | パス | 役割 |
|:---|:---|:---|
| `Accounts` | `lib/omni_archive/accounts.ex` | ユーザー登録・認証・トークン管理のコンテキスト |
| `User` | `lib/omni_archive/accounts/user.ex` | ユーザースキーマ（email, hashed_password） |
| `UserToken` | `lib/omni_archive/accounts/user_token.ex` | セッション・メール確認トークン |
| `UserAuth` | `lib/omni_archive_web/user_auth.ex` | 認証プラグ群 |
| `Scope` | `lib/omni_archive/accounts/scope.ex` | 認証スコープ（`@current_scope`） |

### グローバルナビゲーションバー

`root.html.heex` にアプリ共通のナビバーを配置。ログイン状態に応じて表示を動的に切り替えます。

| 状態 | 表示内容 |
|:---|:---|
| ログイン済み | メールアドレス、設定リンク、ログアウト |
| 未ログイン | 登録リンク、ログインボタン |

### 所有権管理 (User Scoping) とデータ隔離

`PdfSource` に `user_id`（所有者）を追加し、マルチユーザー環境におけるデータ隔離を実現しています。
`Ingestion` コンテキストでの情報フェッチや変更処理はすべて `user_id` によるスコープが適用されており、以下のルールでアクセス制御されます。

- **Admin ロール**: 全ユーザーの `PdfSource` にアクセス可能。ダッシュボードや `/admin/review` での全件管理。
- **User ロール**: 自身が作成（アップロード）した `PdfSource` およびそれに紐づく `ExtractedImage` のみアクセス・編集可能。

他ユーザーのデータアクセス試行に対しては `Ecto.NoResultsError` を発行し、404 エラーページへフォールバックさせて不正操作を防止します。

### 所有者/作業者モデル (ExtractedImage)

`ExtractedImage` にも個別の `owner_id`（アップロード者）と `worker_id`（作業者）の外部キーを持たせています。
現在はこの所有権モデルと `PdfSource.user_id` の二段構えで、将来的なマルチテナントや細かなタスク割り当て基盤としての拡張性を持たせています。

---

## フロントエンドアーキテクチャ

### LiveView + JS Hook 統合

```
LiveView (Elixir)              JS Hook (JavaScript)
────────────────               ──────────────────────
  ↓ push_event                   ↓ Hook インストール (ImageSelection)
  "nudge_crop"  ─────────────>  setData() で位置調整
                                   ↓ cropend イベント
  handle_event  <─────────────  pushEvent("update_crop_data")
  "update_crop_data"           getData(true) を送信
```

### ギャラリー UI アーキテクチャ

*   **Masonry Layout**: CSS Multi-column (`columns-xs`, `break-inside-avoid`) を採用し、Pinterest 風の不規則なグリッドレイアウトを実現。
*   **Lazy Creation**: `Browse` 画面でのページ選択時は DB レコードを作成せず（Write-on-Action）、`Crop` 画面での明示的な保存操作をトリガーとすることで、ゴーストレコードの発生を抑制します。

### 認知アクセシビリティの設計原則

1. **最小認知負荷**: 一画面で一つのタスクのみ
2. **大きなタッチターゲット**: 全ボタン最小 60×60px
3. **明確なフィードバック**: 全操作に視覚的確認
4. **破壊的操作の保護**: 確認ダイアログ必須
5. **線形ナビゲーション**: 前後のみの移動（ジャンプ不可）

### ギャラリー & 管理画面テーマ: 新潟インディゴ＆ハーベストゴールド

公開ギャラリー (`/gallery`) および 管理者レビュー画面 (`/admin/review`) には専用のダークテーマを適用しています。
CSS 変数で `.gallery-container` または `.admin-review-container` スコープに適用し、Lab 画面の基本 UI に影響を与えないように設計されています。

### Lab プロジェクト管理 UI

Lab のプロジェクト一覧（`/lab`）・詳細（`/lab/projects/:id`）には専用の `lab.css` を適用。
`.lab-container` スコープでカードグリッド・ステータスバッジ・画像グリッド等のスタイルを定義し、
Harvest Gold アクセントカラーによるホバーエフェクトとモバイルレスポンシブ対応を実装しています。

| 役割 | 変数名 | HEX | 用途 |
|:---|:---|:---|:---|
| Base Layer | `--gallery-bg` | `#1A2C42` | ギャラリー背景 |
| Accent | `--gallery-accent` | `#E6B422` | ボタン、アクティブボーダー、ホバー |
| Typography | `--gallery-text` | `#E0E0E0` | 本文テキスト (コントラスト比 ≈ 10.4:1) |
| Surface | `--gallery-surface` | `#243B55` | カード背景 |
| Muted | `--gallery-text-muted` | `#A0AEC0` | 補助テキスト、メタ情報 |

---

## 品質チェックパイプライン

`mix review` コマンドで以下を4ステップで逐次実行します：

```
① mix compile --warnings-as-errors    → コンパイル警告ゼロ
② mix credo --strict                  → コードスタイル検査
③ mix sobelow --config                → セキュリティ解析
④ mix dialyzer                        → 型チェック
⑤ mix review.summary                  → PASS/FAIL サマリー
```

各ステップは失敗時に即座に停止し、サマリータスクが実行されることが全チェック通過を意味します。

### 設定ファイル

| ファイル | 役割 |
|:---|:---|
| `.credo.exs` | コードスタイルルール・ノイズ抑制 |
| `.sobelow-conf` | セキュリティチェック設定・除外ルール |
| `.dialyzer_ignore.exs` | 既知の型警告除外 |
