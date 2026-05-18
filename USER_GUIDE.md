# User Guide / 利用者ガイド

This guide is written for the people who actually use OmniArchive day-to-day — workers in supported-employment settings, archivists, reviewers, and gallery visitors. It does **not** assume any programming or server administration knowledge. For technical documentation, see [ARCHITECTURE.md](ARCHITECTURE.md), [IIIF_SPEC.md](IIIF_SPEC.md), and [DEPLOYMENT.md](DEPLOYMENT.md).

このガイドは OmniArchive を日常的に使う方々 — 就労継続支援の現場のスタッフ、アーキビスト、レビュアー、ギャラリー閲覧者 — に向けて書かれています。プログラミングやサーバー運用の知識は前提としません。技術ドキュメントは [ARCHITECTURE.md](ARCHITECTURE.md) / [IIIF_SPEC.md](IIIF_SPEC.md) / [DEPLOYMENT.md](DEPLOYMENT.md) を参照してください。

---

## Table of Contents / 目次

1. [Roles and screens / 役割と画面](#1-roles-and-screens--役割と画面)
2. [Logging in / ログイン](#2-logging-in--ログイン)
3. [Lab: the 5-step wizard / Lab — 5 ステップウィザード](#3-lab-the-5-step-wizard--lab--5-ステップウィザード)
4. [Gallery: browsing published images / Gallery — 公開画像の閲覧](#4-gallery-browsing-published-images--gallery--公開画像の閲覧)
5. [Administrator workflow / 管理者ワークフロー](#5-administrator-workflow--管理者ワークフロー)
6. [FAQ and troubleshooting / FAQ・トラブルシューティング](#6-faq-and-troubleshooting--faqトラブルシューティング)

---

## 1. Roles and screens / 役割と画面

OmniArchive has two user roles and three main screens.

| Role / 役割 | What they do / 役割の内容 |
|:---|:---|
| **User** (`user`) | Uploads sources, crops figures, enters metadata, submits work for review / アップロード・クロップ・ラベル付け・レビュー提出 |
| **Admin** (`admin`) | Approves or returns submitted work, manages user accounts, manages the trash / 承認・差し戻し・ユーザー管理・ゴミ箱管理 |

| Screen / 画面 | URL | Who can see it / 閲覧可能なユーザー |
|:---|:---|:---|
| **Lab** | `/lab` | Logged-in users (own projects only); admins see all / ログイン済みユーザー（自分のプロジェクトのみ）。管理者は全件 |
| **Gallery** | `/gallery` | Anyone — no login required / 誰でも閲覧可能 |
| **Admin** | `/admin` | Admin role only / 管理者ロールのみ |

> **Public registration is disabled.** Accounts are created by administrators using an invitation model. Contact your administrator if you need an account.
>
> **公開登録は無効化されています。** アカウントは管理者が招待制で作成します。新規アカウントが必要な場合は管理者にご連絡ください。

---

## 2. Logging in / ログイン

1. Open <http://localhost:4000> (or the URL your administrator provides) / ブラウザで該当 URL を開きます
2. Click **「ログイン」** in the top-right navigation bar / 右上の **ログイン** をクリック
3. Enter your email address and password / メールアドレスとパスワードを入力

After login you will land on `/lab` (the project list) if you are a user, or `/admin` if you are an administrator.

ログイン後、一般ユーザーは `/lab`（プロジェクト一覧）、管理者は `/admin` に遷移します。

> **Forgot your password?** Click **「パスワードをお忘れですか？」** on the login screen. A reset email will be sent if your address is registered.
>
> **パスワードを忘れた場合**: ログイン画面の **パスワードをお忘れですか？** をクリックすると、登録メールアドレス宛にリセット用リンクが届きます。

---

## 3. Lab: the 5-step wizard / Lab — 5 ステップウィザード

The Lab is the internal workspace where you create IIIF assets. It is designed as a **linear wizard** so you always know exactly where you are and what to do next.

Lab は IIIF アセットを作成する内部ワークスペースです。**線形のウィザード形式**で設計されており、現在地と次にすべきことが常に明確になります。

![Lab Wizard Interface](priv/static/images/wizard.jpg)

| Step | Icon | Where / 画面 | What you do / 操作内容 |
|:---:|:---:|:---|:---|
| 1 | 📄 | `/lab/upload` | Upload a PDF or PNG ZIP / PDF または PNG の ZIP をアップロード |
| 2 | 🔍 | `/lab/browse/:id` | Select pages that contain figures / 図版を含むページを選択 |
| 3 | ✂️ | `/lab/crop/:id/:page` | Draw a polygon around the figure / 図版を多角形で囲む |
| 4 | 🏷️ | `/lab/label/:image_id` | Enter the caption and metadata / キャプション・メタデータを入力 |
| 5 | ✅ | `/lab/finalize/:image_id` | Submit for review / レビュー依頼を提出 |

### Step 1 — Upload / アップロード

1. Go to `/lab` and click **「新規アップロード」** / `/lab` に移動し **新規アップロード** をクリック
2. Choose a conversion mode / 変換モードを選択
   - 🖤 **モノクロ（高速）** — for line drawings and most reports (default) / 線画・大半の報告書に最適（既定）
   - 🎨 **カラー（標準）** — for photographs or colored figures / 写真・彩色図向け
3. Drop a file (or click to choose). Accepted: `.pdf`, `.zip` (PNG pages only) / ファイルをドロップまたは選択。受付形式: `.pdf` / `.zip`（PNG のみ）
4. Watch the progress bar. PDFs are converted in 10-page chunks; you can leave the screen and come back / プログレスバーで進捗を確認。10 ページ単位で変換されるため、画面を離れても作業は継続されます

> **Why two upload formats?** PDFs are converted to PNG at 300 DPI by `pdftoppm`. If you already have high-quality PNG scans, packaging them in a ZIP skips re-conversion. The system enforces zip-slip protection, magic-byte verification, and size limits when extracting ZIPs.
>
> **なぜ 2 つの形式に対応しているか**: PDF は `pdftoppm` で 300 DPI の PNG に変換します。すでに高品質な PNG スキャンがある場合は ZIP でまとめてアップロードすることで再変換を回避できます。ZIP 展開時は zip-slip 対策・magic byte 検証・サイズ上限を強制しています。

### Step 2 — Browse and select pages / ページ選択

After conversion completes, all pages appear as a thumbnail grid. Click a thumbnail to start cropping that page.

変換完了後、全ページがサムネイルグリッドで表示されます。クロップしたいページをクリックします。

> **No database record is created yet** (Write-on-Action policy). Browsing is read-only. A record is created only when you actually save a crop in Step 3.
>
> **この時点ではデータベースにレコードは作成されません**（Write-on-Action ポリシー）。閲覧は読み取り専用で、Step 3 でクロップを保存して初めてレコードが作られます。

### Step 3 — Crop the figure / 図版をクロップ

1. **Click** to add polygon vertices around the figure / クリックで頂点を追加し、図版を囲みます
2. **Double-click** (or click the first point, or press **Enter**) to close the polygon and save / **ダブルクリック**（または始点クリック / **Enter**）で多角形を閉じて保存
3. Use the **D-Pad nudge buttons** (↑↓←→) or arrow keys to shift the whole polygon by 10 px / **D-Pad ナッジボタン**または矢印キーで全体を 10px 単位で微調整
4. **Clear / Undo** reverts your work — use it freely / **クリア / Undo** で何度でも描き直せます

| Limit / 制限 | Value / 値 |
|:---|:---|
| Max vertices / 最大頂点数 | 64 |
| Max coordinate / 座標上限 | 20,000 px |
| Max rectangle side / 矩形辺上限 | 20,000 px |
| Max cropped area / 切り出し面積上限 | 100,000,000 px² |

These limits are enforced on the server before libvips processes the geometry, so very large or malformed selections are rejected with a clear error message.

これらの上限はサーバー側で libvips 処理前に検証されます。範囲外の選択は明確なエラーメッセージで拒否されます。

### Step 4 — Add the label and metadata / ラベリング

Enter the caption, label, and any other fields defined by the active domain profile (for example: site name, period, artifact type for the Archaeology profile). All inputs **save automatically** as you type.

キャプション・ラベル・有効ドメインプロファイルで定義された各メタデータ項目を入力します。入力内容は**自動保存**されます。

> **Required fields are marked.** The label format and any vocabulary restrictions are enforced by the domain profile. If validation fails, the field will show a clear inline error.
>
> **必須項目には印が付きます。** ラベル形式や語彙制約はドメインプロファイルで定義され、違反時はフィールド直下に明確なエラーが表示されます。

### Step 5 — Submit for review / レビュー提出

Review your work on the Finalize screen and click **「レビュー依頼」**. The project moves from `wip` to `pending_review` and the administrator is notified.

Finalize 画面で内容を確認し、**レビュー依頼** をクリックすると、プロジェクトは `wip` → `pending_review` に遷移し、管理者に通知されます。

### If your work is returned / 差し戻された場合

If an administrator returns your project, the **「要修正」** tab on the Lab dashboard will show it along with the administrator's message. Fix the issues, then submit again — the project moves back to `pending_review`.

差し戻されたプロジェクトは Lab ダッシュボードの **「要修正」** タブに、管理者からのメッセージとともに表示されます。修正後に再度「レビュー依頼」を行うと、`pending_review` に戻ります。

| Project status / プロジェクトステータス | Meaning / 意味 |
|:---|:---|
| `wip` | Work in progress / 作業中 |
| `pending_review` | Waiting for admin review / 審査待ち |
| `returned` | Returned with a message / 差し戻し（メッセージ付き） |
| `approved` | Approved — assets are public / 承認済み — 公開状態 |

---

## 4. Gallery: browsing published images / Gallery — 公開画像の閲覧

The Gallery (`/gallery`) is the **public-facing** view. No login is required. Only `approved` and `published` images appear here.

Gallery (`/gallery`) は **公開閲覧用** の画面で、ログイン不要です。`approved` かつ `published` の画像のみが表示されます。

![Gallery Interface](priv/static/images/gallery.jpg)

### Browsing / 閲覧

- **Card grid** — every published image is shown as a card with thumbnail, label, and caption / 公開画像は全件カード形式で表示されます
- **Click a card** to open the IIIF zoom modal (OpenSeadragon). Use the mouse wheel, drag, or the on-screen buttons to pan and zoom. Press **Esc** or click the background to close / カードクリックで IIIF 拡大モーダル（OpenSeadragon）が開きます。マウスホイール・ドラッグ・ボタンで拡大縮小・移動できます。**Esc** または背景クリックで閉じます

> Before an admin approves an image, no PTIF tile pyramid exists yet, so the modal falls back to an SVG-based viewer that preserves the polygon shape. Once approved, the full IIIF tile experience is enabled automatically.
>
> 管理者承認前は PTIF が未生成のため、モーダルは多角形を保持した SVG ベースのビューアにフォールバックします。承認後は自動的に IIIF タイル配信に切り替わります。

### Search and filter / 検索・絞り込み

The search bar runs PostgreSQL full-text search over captions. The facet filters on the side panel come from the **active domain profile** — for example, period and artifact type for the Archaeology profile, or your custom facets when using a YAML profile.

検索バーはキャプションに対する PostgreSQL 全文検索を実行します。サイドパネルのファセット絞り込み項目は **有効ドメインプロファイル** に由来します（Archaeology プロファイルでは時代・遺物種別など、YAML プロファイルではカスタム定義のファセット）。

Results paginate with a **「もっと見る」** button (10 items per page). Changing the search or any filter resets to page 1.

検索結果は **「もっと見る」** ボタンで 10 件ずつ追加表示されます。検索語やフィルタを変更すると 1 ページ目から表示されます。

### Downloading a high-resolution crop / 高解像度クロップのダウンロード

Published images expose a download link (`/download/:id`) that returns the cropped image at full resolution. Only published images can be downloaded.

公開済み画像は `/download/:id` から高解像度クロップ画像をダウンロードできます。公開済み以外はダウンロード不可です。

### IIIF endpoints / IIIF エンドポイント

Anyone can plug these URLs into a IIIF viewer such as Mirador or Universal Viewer:

以下の URL は Mirador / Universal Viewer などの IIIF ビューアにそのまま投入できます。

```
# Per-image Manifest / 個別画像 Manifest
GET /iiif/manifest/{identifier}

# Per-source Manifest (all published canvases in a PDF) / PdfSource 単位 Manifest
GET /iiif/presentation/{source_id}/manifest

# Image API tile / Image API タイル
GET /iiif/image/{identifier}/{region}/{size}/{rotation}/{quality}

# Image metadata (info.json) / 画像メタデータ
GET /iiif/image/{identifier}/info.json
```

For the full endpoint specification, parameters, and error responses, see [IIIF_SPEC.md](IIIF_SPEC.md).

エンドポイント仕様・パラメータ・エラーレスポンスの詳細は [IIIF_SPEC.md](IIIF_SPEC.md) を参照してください。

---

## 5. Administrator workflow / 管理者ワークフロー

Administrators see an additional menu in the navigation bar. The main admin screens are:

管理者にはナビバーに追加メニューが表示されます。主な画面は次のとおりです。

| Screen / 画面 | URL | Purpose / 目的 |
|:---|:---|:---|
| Dashboard / ダッシュボード | `/admin/dashboard` | Overview of all users' projects and review queue / 全ユーザーのプロジェクト概況とレビューキュー |
| Review / レビュー | `/admin/review` | Approve, return, or delete submitted items / 承認・差し戻し・削除 |
| Users / ユーザー管理 | `/admin/users` | Create, edit, deactivate users / 作成・編集・停止 |
| Custom fields / カスタムフィールド | `/admin/fields` | Per-deployment field configuration / デプロイ別のフィールド設定 |
| Trash / ゴミ箱 | `/admin/trash` | Restore or permanently delete soft-deleted projects / 論理削除済みプロジェクトの復元・完全削除 |

### Approving or returning work / 承認・差し戻し

1. Open `/admin/review` — submitted items appear in the `pending_review` list / `/admin/review` を開き、`pending_review` 一覧を確認
2. Click an item to view its images and metadata side-by-side / クリックすると画像とメタデータが並列表示されます
3. Choose one of:
   - **「承認」** — promotes the project to `approved`. Public PTIF generation is triggered **lazily at this moment** so resources are not wasted on work-in-progress items. / `approved` に昇格。**この時点で初めて** 公開用 PTIF が遅延生成されます
   - **「差し戻し」** — returns the project to the user with a required message. Both project-level and per-image return reasons are supported. / メッセージ付きでユーザーに差し戻します（プロジェクトレベル・画像レベル両対応）
   - **「削除」** — soft-deletes the project (moves to Trash). Projects with any published images are **locked from deletion** and show a lock icon. / 論理削除（ゴミ箱へ移動）。公開済み画像を含むプロジェクトは削除不可で、ロックアイコンが表示されます

> Bulk approve, bulk return, and bulk delete are available from the review list when multiple items are selected.
>
> 一覧で複数選択すると、一括承認・一括差し戻し・一括削除を実行できます。

### Managing users / ユーザー管理

`/admin/users` allows administrators to create accounts (invitation model), reset passwords, change roles, and deactivate users. Public self-registration is intentionally disabled.

`/admin/users` でアカウント作成（招待制）・パスワードリセット・ロール変更・ユーザー停止を行えます。公開セルフ登録は意図的に無効化されています。

### Trash management / ゴミ箱管理

Deleted projects move to `/admin/trash`. From there you can either **restore** them (back to their previous status) or **permanently delete** them. Permanent deletion also removes the associated source files, extracted images, and PTIFs from disk.

削除されたプロジェクトは `/admin/trash` に移動します。ここから **復元**（直前のステータスに戻す）または **完全削除** が可能です。完全削除を行うと、関連するソースファイル・抽出画像・PTIF もディスクから削除されます。

---

## 6. FAQ and troubleshooting / FAQ・トラブルシューティング

### Q. Upload fails immediately. / アップロードがすぐに失敗します

Check the file size and type:

| Check / 確認項目 | Limit / 上限 |
|:---|:---|
| File extension / 拡張子 | `.pdf` or `.zip` only |
| ZIP contents / ZIP 内容 | PNG files only (verified by magic bytes) / PNG のみ（magic byte で検証） |
| Source size / ソースサイズ | `MAX_SOURCE_UPLOAD_BYTES` (env var) |
| ZIP extracted size / ZIP 展開後サイズ | `ZIP_MAX_EXTRACTED_BYTES` |
| PDF pages / PDF ページ数 | `PDF_MAX_PAGES` |
| ZIP pages / ZIP ページ数 | `ZIP_MAX_PAGES` |

Ask your administrator to confirm or raise these limits if necessary. They are configured via environment variables — see [DEPLOYMENT.md](DEPLOYMENT.md) and `config :omni_archive, :ingestion` in `config/runtime.exs`.

これらは環境変数で設定可能です。詳細は [DEPLOYMENT.md](DEPLOYMENT.md) および `config/runtime.exs` の `config :omni_archive, :ingestion` を参照してください。

### Q. PDF conversion hangs or is very slow. / PDF 変換が遅い／止まっているように見えます

Large PDFs (200+ pages) are processed in 10-page chunks. The progress bar updates after each chunk, not after each page, so it may pause for several seconds between updates. This is normal.

If conversion truly stalls (no progress for several minutes), check:

- Server free memory — the resource monitor reduces concurrency below 20 % free memory / 空きメモリが 20 % を下回ると並列度を自動的に下げます
- `pdftoppm` is installed and on `PATH` / `pdftoppm` がインストールされ `PATH` 上にあること
- libvips is installed (used after extraction) / libvips がインストールされていること

大規模 PDF（200+ ページ）は 10 ページ単位で逐次処理されるため、進捗バーはチャンク完了ごとに更新されます。数秒〜十数秒の停止は正常です。数分以上進捗がない場合は上記を確認してください。

### Q. Cropping doesn't close when I double-click. / ダブルクリックしてもクロップが閉じません

You need **at least 3 vertices** to close a polygon. Add another point, then double-click — or press **Enter** as an alternative.

多角形を閉じるには **頂点が 3 つ以上** 必要です。点を追加してからダブルクリック、または **Enter** キーを試してください。

### Q. Saved crop looks slightly off from what I drew. / 保存されたクロップが描画と少しずれています

Crop edges are slightly feathered (Gaussian) and the boundary color is sampled from the source so that the cropped figure blends cleanly. This is intentional. If you need a hard rectangle edge, draw a 4-vertex rectangle.

クロップ境界は Gaussian フェザリングと境界色サンプリングを行うため、描画線とわずかに差が出る場合があります（意図的な仕様です）。完全な矩形が必要な場合は 4 頂点で長方形を描いてください。

### Q. My image is not in the Gallery after the admin approved it. / 承認されたのに Gallery に表示されません

Approval triggers PTIF generation, which takes a few seconds to a few minutes per image. Refresh the Gallery after a moment. If the image still does not appear:

- Confirm the project status is `approved` and the image status is `published` (visible in the admin dashboard) / プロジェクトが `approved`、画像が `published` であることを管理ダッシュボードで確認
- Check that no validation error blocked publication (required fields, label format, etc.) / 必須項目・ラベル形式などのバリデーションエラーで公開がブロックされていないか確認
- Ask the admin to check server logs for libvips / PTIF errors / libvips / PTIF のエラーがサーバーログに出ていないか管理者に確認を依頼

### Q. I uploaded the wrong PDF. Can I delete it? / 誤った PDF をアップロードしたので削除したいです

Yes — from the project list, open the project and choose **「削除」**. The project moves to the Trash (admin only) and can be permanently removed later. **Projects with published images cannot be deleted** until those images are unpublished first.

プロジェクト一覧から該当プロジェクトを開き **削除** を選択してください。ゴミ箱（管理者のみアクセス可）に移動し、後で完全削除も可能です。**公開済み画像を含むプロジェクトは、先に画像を非公開にしない限り削除できません**。

### Q. I lost my password. / パスワードを忘れました

Use **「パスワードをお忘れですか？」** on the login screen. If email is not yet configured on your deployment, contact your administrator — they can reset your password from `/admin/users`.

ログイン画面の **パスワードをお忘れですか？** を使用してください。メール設定が未完了の環境では、管理者に依頼すると `/admin/users` からパスワードをリセットできます。

### Q. Gallery images load slowly. / Gallery の画像読み込みが遅いです

Tiles are cached on first access and served from disk afterward. The first view of a never-zoomed image generates new tiles on the fly — subsequent views are much faster. If load times remain consistently slow, ask your administrator to check the IIIF tile cache directory and PostgreSQL connection pool size (`POOL_SIZE`).

タイルは初回アクセス時に生成・キャッシュされ、以降はディスクから高速配信されます。常時遅い場合は、管理者に IIIF タイルキャッシュディレクトリと PostgreSQL 接続プール (`POOL_SIZE`) を確認してもらってください。

### Q. Can I customize which metadata fields appear? / 表示するメタデータ項目をカスタマイズできますか？

Yes — via a **domain profile**. The built-in `Archaeology` and `GeneralArchive` profiles cover common cases. For custom fields, write a YAML profile and set `OMNI_ARCHIVE_PROFILE_YAML` to its path. See [PROFILES.md](PROFILES.md) for the full YAML schema and examples.

はい — **ドメインプロファイル** で切り替え可能です。組み込みの `Archaeology` / `GeneralArchive` のほか、YAML ファイルを書いて `OMNI_ARCHIVE_PROFILE_YAML` でパスを指定すればカスタムフィールド構成を定義できます。YAML スキーマと例は [PROFILES.md](PROFILES.md) を参照してください。

### Q. Something else is wrong. / 上記以外の問題が起きています

Open an Issue on [GitHub](https://github.com/SilentMalachite/OmniArchive/issues) — English or Japanese is fine. Include:

1. What you tried to do / 試した操作
2. What you expected / 期待した結果
3. What happened instead / 実際の挙動
4. A screenshot if possible / スクリーンショット（あれば）
5. Browser, OS, and approximate time of the issue / ブラウザ・OS・発生時刻

For bug reports from administrators or developers, see the troubleshooting section of [DEPLOYMENT.md](DEPLOYMENT.md) first — many issues are environment-related.

管理者・開発者の方は、まず [DEPLOYMENT.md](DEPLOYMENT.md) のトラブルシューティング節を確認してください。多くの問題は環境設定起因です。
