# OmniArchive

[![Elixir](https://img.shields.io/badge/Elixir-1.15+-4B275F?logo=elixir)](https://elixir-lang.org/)
[![Phoenix](https://img.shields.io/badge/Phoenix-1.8+-E8562A?logo=phoenix-framework)](https://www.phoenixframework.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15+-4169E1?logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![IIIF](https://img.shields.io/badge/IIIF-v3.0-2873AB)](https://iiif.io/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

> **PDFファイルを IIIF アセットに変換する Elixir/Phoenix アプリケーション**

OmniArchive は、静的な PDFファイル を、国際的な画像相互運用フレームワーク [IIIF (International Image Interoperability Framework)](https://iiif.io/) に準拠したリッチなデジタルアセットに変換するためのツールです。

就労継続支援の現場で利用されることを想定し、**認知アクセシビリティ**を最優先にした UI 設計を採用しています。

---

## ✨ 主な特徴

### 🧙 ウィザード型インスペクタ (Lab)

![Lab Wizard Interface](priv/static/images/wizard.jpg)

直感的な **5 ステップ**のウィザード形式で、PDF から IIIF アセットを作成します。

| ステップ | アイコン | 内容 |
|:---:|:---:|:---|
| **1. アップロード** | 📄 | PDF をアップロードすると、全ページが自動的に高解像度 PNG に変換されます。「要修正」タブで差し戻された図版の修正も可能です |
| **2. ページ選択** | 🔍 | サムネイルグリッドから図版を含むページを選択します（レコードは未作成 — Write-on-Action） |
| **3. クロップ** | ✂️ | オリジナルの JS Hook を使用。**ダブルクリック（またはダブルタップ）**で範囲を確定・保存（ここで初めてレコード作成） |
| **4. ラベリング** | 🏷️ | メタデータを入力します。保存完了後、自動的に PTIF 生成がバックグラウンドで開始されます |
| **5. レビュー提出** | ✅ | 内容を確認し、レビュー依頼を提出します（提出後は編集がロックされます） |

### 🏛️ Stage-Gate ワークフロー (Lab → Gallery)

品質管理のため、内部作業と公開を明確に分離しています。

| ステージ | 説明 |
|:---:|:---|
| **Lab (内部)** | プロジェクト一覧（`/lab`）から PDF を選択し、アップロード・クロップ・ラベリングを行う内部ワークスペース |
| **プロジェクトワークフロー** | プロジェクト単位の作業進捗管理（作業中 → 審査待ち → 差し戻し/承認）。一般ユーザーが「作業完了」として提出し、管理者が承認または差し戻し（メッセージ付き）を行います |
| **承認** | 管理者が `/admin/review` で内容を確認、承認、差し戻し、または削除（一括削除対応）を行います |
| **差し戻し・再提出** | 差し戻されたアセットは「要修正」タブに表示され、修正後に再提出できます。プロジェクトレベル・画像レベル両方の差し戻し理由を確認可能です |
| **Gallery (公開)** | 承認されたアセットを表示。カードクリックで SVG ベースの拡大モーダルを表示。高解像度クロップ画像のダウンロードも可能です |
| **管理者ダッシュボード** | 管理者が `/admin` で全ユーザーのデータを管理。非同期ロードによる高速表示。一括削除やユーザー管理が可能です |
| **ゴミ箱管理** | 削除されたプロジェクトは `/admin/trash` で管理。復元または完全削除が可能です。公開済プロジェクトは削除から保護されます |

### 🔍 検索・発見

![Gallery Interface](priv/static/images/gallery.jpg)

- **全文検索**: キャプションの PostgreSQL FTS (tsvector + GIN インデックス)
- **ファセット検索**: 遺跡名・時代・遺物種別によるフィルタリング

### ♿ 認知アクセシビリティ

- **ギャラリー & 管理画面テーマ**: 「新潟インディゴ＆ハーベストゴールド」— Deep Sea Indigo (#1A2C42) 背景 + Harvest Gold (#E6B422) アクセント、Mist Grey (#E0E0E0) テキストでコントラスト比約 10.4:1（WCAG AAA 準拠）。公開ギャラリーに加え、管理者レビュー画面にも適用されています。
- **線形フロー**: ウィザードパターンで迷わない操作
- **D-Pad ナッジコントロール**: 3×3 Grid 配置の 方向ボタンによるクロップ範囲の微調整（精密なドラッグ操作が不要）。物理コントローラーを意識した D-Pad レイアウト。
- **大きなボタン**: 全ての操作ボタンは D-Pad を含め最小 60×60px（主要ボタンは 64×64px）
- **即時フィードバック**: 明確な成功・エラーメッセージ
- **手動入力**: AI による自動抽出は行わず、全ての選択は人が行います

### 🔒 認証システム & 権限管理

- **ロールベースアクセス制御 (RBAC)**: `admin` と `user` ロールによる権限管理。
- **プロジェクトの所有権分離 (User Scoping)**: `PdfSource` は「所有者 (`user_id`)」を持ちます。管理者は全データにアクセスできますが、一般ユーザーは自身がアップロードしたプロジェクト（およびその中の画像）のみ閲覧・編集が可能なように堅牢にスコープされます。他人のプロジェクトへはアクセスできません。
- **セッションベース認証**: `phx.gen.auth` によるセッション管理。Lab と Admin はログイン必須です
- **招待制モデル**: 公開ユーザー登録を制限し、管理者によるアカウント作成・招待モデルを採用しています
- **グローバルナビバー**: ログイン状態に応じたナビゲーション。管理者には管理メニューが表示されます
- **複数ユーザーの協力モデル**: `ExtractedImage` にも `owner_id` / `worker_id` の追跡を持たせ、管理者が全体の作業状況を把握できます。

### 🛡️ データ整合性と信頼性

- **厳格なバリデーション**: ラベル形式 (`fig-1-1`) や自治体名（市町村必須）の強制により、書誌情報の品質を担保
- **ファイルバージョニング**: アップロードファイルへのタイムスタンプ付与により、ブラウザキャッシュの衝突（ゴースト画像）を完全に防止
- **Write-on-Action**: 閲覧操作と保存操作を明確に分離し、意図しない空レコードの作成を防止
- **ソフトデリート**: プロジェクト削除は `deleted_at` タイムスタンプによる論理削除。ゴミ箱からの復元または完全削除が可能
- **公開済みプロジェクト保護**: Gallery に公開済みの画像を含むプロジェクトは削除不可。UI 上でロックアイコンを表示
- **プロジェクト ワークフロー管理**: プロジェクト単位で作業進捗を管理（`wip` → `pending_review` → `returned` / `approved`）。差し戻し時には管理者メッセージを記録可能

### ⚡ 並列処理パイプライン

- **リソース適応型並列処理**: CPU コア数・空きメモリを自動検出し、最適な並列度で処理
- **メモリガード**: 空きメモリが 20% 未満になると並列度を自動縮小し、スワップを回避
- **リアルタイム進捗表示**: PubSub によるバッチ処理の進捗をリアルタイムで表示
- **UI レスポンス保証**: 1 CPU コアを常に UI スレッド用に確保

### 🖼️ IIIF v3.0 準拠

- **Image API v3.0**: PTIF からの動的タイル生成 + キャッシュ
- **Presentation API v3.0**: JSON-LD 形式の Manifest（英語/日本語対応）
  - **個別画像 Manifest**: `GET /iiif/manifest/:identifier` — 単一画像の Manifest
  - **PdfSource 単位 Manifest**: `GET /iiif/presentation/:source_id/manifest` — 資料内の公開済み画像を Canvas として集約

### 🔒 品質チェック (`mix review`)

単一コマンドで品質・セキュリティ・型安全性を検証する自動レビューパイプライン：

- **コンパイル**: `--warnings-as-errors` で警告ゼロを保証
- **Credo**: `--strict` モードでコードスタイルを検査
- **Sobelow**: セキュリティ脆弱性の静的解析
- **Dialyzer**: 型レベルの安全性チェック

---

## 🛠️ 技術スタック

| カテゴリ | 技術 |
|:---|:---|
| 言語 / フレームワーク | Elixir 1.15+ / Phoenix 1.8+ (LiveView) |
| データベース | PostgreSQL 15+ (JSONB メタデータ) |
| 画像処理 | [vix](https://github.com/akash-akya/vix) (libvips ラッパー) |
| PDF 変換 | [poppler-utils](https://poppler.freedesktop.org/) (pdftoppm) |
| フロントエンド | Phoenix LiveView + 独自の JavaScript Hook (ImageSelection) |
| コンテナ | Docker (マルチステージビルド) |

---

## 🚀 セットアップ

### 前提条件

以下のソフトウェアがインストールされている必要があります：

- **Elixir** 1.15 以上
- **Erlang/OTP** 24 以上
- **PostgreSQL** 15 以上
- **libvips** (画像処理)
- **poppler-utils** (PDF 変換)
- **Node.js** / npm (アセットビルド)

#### macOS (Homebrew)

```bash
brew install elixir postgresql@15 vips poppler node
```

#### Ubuntu / Debian

```bash
sudo apt install elixir erlang postgresql libvips-dev poppler-utils nodejs npm
```

#### Windows (ネイティブ)

以下のソフトウェアをインストールしてください：

| ソフトウェア | 説明 | ダウンロード |
|:---|:---|:---|
| **Elixir & Erlang/OTP** | プリコンパイル済み Windows インストーラーを使用 | [Elixir Installer](https://elixir-lang.org/install.html#windows) |
| **PostgreSQL 15+** | 公式 Windows インストーラー | [PostgreSQL Downloads](https://www.postgresql.org/download/windows/) |
| **Visual Studio Build Tools** | vix/libvips NIF のコンパイルに**必須** | [VS Build Tools](https://visualstudio.microsoft.com/ja/visual-cpp-build-tools/) |
| **Git for Windows** | バージョン管理 | [Git for Windows](https://gitforwindows.org/) |
| **poppler-utils** | PDF 変換 (pdftoppm) | [poppler releases](https://github.com/oschwartz10612/poppler-windows) |

> [!IMPORTANT]
> **Visual Studio Build Tools** のインストール時に「**C++ によるデスクトップ開発**」ワークロードを必ず選択してください。
> これがないと `vix` (libvips) NIF のコンパイルに失敗します。

> [!TIP]
> PostgreSQL インストール後、`C:\Program Files\PostgreSQL\15\bin` を **システム環境変数 PATH** に追加してください。
> コマンドプロンプトで `psql --version` が実行できれば設定完了です。

**セットアップ手順 (PowerShell / コマンドプロンプト):**

```powershell
# 1. リポジトリをクローン
git clone https://github.com/SilentMalac/OmniArchive.git
cd OmniArchive

# 2. 依存パッケージをインストール
mix deps.get

# 3. データベースのセットアップ
mix ecto.setup

# 4. 開発サーバーを起動
mix phx.server
```

> [!NOTE]
> **vix 関連のエラーが発生した場合**: Visual Studio Build Tools の「C++ によるデスクトップ開発」が正しくインストールされていることを確認してください。
> インストール後は**コマンドプロンプトを再起動**する必要があります。

### インストール手順

```bash
# 1. リポジトリをクローン
git clone https://github.com/SilentMalac/OmniArchive.git
cd OmniArchive

# 2. 依存パッケージをインストール
mix setup

# 3. （必要に応じて）データベース設定を編集
#    config/dev.exs の username / password を環境に合わせてください

# 4. 開発サーバーを起動
mix phx.server
```

ブラウザで [`http://localhost:4000/lab`](http://localhost:4000/lab) にアクセスしてください。

> [!TIP]
> **初回ログイン**: `mix ecto.setup` でデフォルト管理者ユーザーが自動作成されます。
> - **メール**: `admin@example.com`
> - **パスワード**: `password1234`

---

## 📖 使い方

### 1. PDF をアップロード

`/lab` にアクセスし、PDF ファイルをアップロードします。
アップロードされた PDF は自動的に 300 DPI の PNG 画像に変換されます。

### 2. ページを選択

変換されたページがサムネイルグリッドとして表示されます。
図版や挿絵を含むページをクリックして選択してください。

> **注意**: この段階ではデータベースにレコードは作成されません（Write-on-Action ポリシー）。

### 3. 図版をクロップ

独自の JavaScript Hook (`ImageSelection`) を使用して、ページ上の図版の範囲を指定します。

- **D-Pad ナッジボタン** (↑↓←→): 10px 単位で範囲を微調整。キーボードの矢印キーでも操作可能です。
- **ダブルクリック保存**: 選択範囲をダブルクリック（またはダブルタップ）で確定・保存します。**この操作で初めてレコードが作成されます。**

### 4. ラベリング（メタデータ入力）

キャプション（図の説明）、ラベル（識別名）、遺跡名・時代・遺物種別などのメタデータを入力してください。
自動保存機能により、入力値はリアルタイムで保存されます。クロップ範囲が未設定の場合、保存はブロックされます。

### 5. レビュー提出

確認画面で入力内容を確認し、「保存」を押します。
システムが以下を自動的に行います：

1. クロップ画像の生成
2. ピラミッド型 TIFF (PTIF) への変換
3. IIIF Manifest の登録

### 6. 承認・公開

1. `/lab/approval` で作業者がアイテムを「レビュー依頼」として提出します。
2. `/admin/review` で管理者が内容を確認し、承認すると `/gallery` に公開されます。
3. 管理者は必要に応じて、アイテムの一括削除やユーザー管理を行うことができます。

### 7. 検索

`/lab/search` で、遺跡名・時代・遺物種別・キャプションから画像を検索できます。

### IIIF エンドポイント

保存完了後、以下のエンドポイントからアクセスできます：

```
# Manifest (JSON-LD) — 個別画像
GET /iiif/manifest/{identifier}

# Manifest (JSON-LD) — PdfSource 単位（資料全体）
GET /iiif/presentation/{source_id}/manifest

# Image API (タイル)
GET /iiif/image/{identifier}/{region}/{size}/{rotation}/{quality}

# Image Info
GET /iiif/image/{identifier}/info.json
```

---

## 🐳 Docker デプロイ

```bash
# イメージをビルド
docker build -t omni_archive .

# コンテナを起動
docker run -d \
  -p 4000:4000 \
  -e DATABASE_URL="ecto://user:pass@host/omni_archive_prod" \
  -e SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  -e PHX_HOST="your-domain.com" \
  omni_archive

# データベースマイグレーション
docker exec <container_id> /app/bin/migrate
```

詳細なデプロイ手順は [DEPLOYMENT.md](DEPLOYMENT.md) を参照してください。

---

## 📦 OTP リリースビルド

Docker を使わずにローカルでリリースビルドを作成できます。

### 前提条件

- Elixir 1.15+ / Erlang/OTP 24+
- PostgreSQL 15+
- libvips / poppler-utils
- Node.js / npm

### ビルド手順

```bash
# 1. 本番用依存を取得
MIX_ENV=prod mix deps.get

# 2. npm 依存をインストール
cd assets && npm install && cd ..

# 3. アプリケーションをコンパイル
MIX_ENV=prod mix compile

# 4. アセットをビルド・ダイジェスト
MIX_ENV=prod mix assets.deploy

# 5. OTP リリースを生成
MIX_ENV=prod mix release
```

> **⚠️ 注意**: Phoenix 1.8 の colocated hooks を使用しているため、`mix compile` を `mix assets.deploy` より先に実行する必要があります。

### 起動 (Linux / macOS)

```bash
# 環境変数を設定
export DATABASE_URL="ecto://user:pass@localhost/omni_archive_prod"
export SECRET_KEY_BASE="$(mix phx.gen.secret)"
export PHX_HOST="localhost"

# データベースマイグレーション
_build/prod/rel/omni_archive/bin/migrate

# サーバー起動
_build/prod/rel/omni_archive/bin/server
```

### 起動 (Windows)

Windows では `.bat` スクリプトを使用します：

```powershell
# 環境変数を設定
$env:DATABASE_URL = "ecto://user:pass@localhost/omni_archive_prod"
$env:SECRET_KEY_BASE = "your-secret-key-base"
$env:PHX_HOST = "localhost"

# リリースディレクトリに移動
cd _build\prod\rel\omni_archive\bin

# データベースマイグレーション
.\omni_archive.bat eval "OmniArchive.Release.migrate"

# サーバー起動
.\omni_archive.bat start
```

> [!TIP]
> `SECRET_KEY_BASE` は事前に `mix phx.gen.secret` で生成した値を使用してください。

> [!NOTE]
> **Windows サービスとして登録**: OTP リリースは Windows サービスとしてインストールすることも可能です。
> `omni_archive.bat install` コマンドでサービスとして登録でき、OS 起動時に自動的にサーバーが立ち上がるようになります。
> 詳細は `omni_archive.bat help` を参照してください。

---

## 📁 ディレクトリ構成

```
OmniArchive/
├── lib/
│   ├── omni_archive/
│   │   ├── ingestion/               # 取り込みパイプライン
│   │   │   ├── pdf_source.ex            # PDF 管理スキーマ
│   │   │   ├── extracted_image.ex       # 抽出画像スキーマ
│   │   │   ├── pdf_processor.ex         # PDF→PNG 変換
│   │   │   └── image_processor.ex       # PTIF 生成・タイル切り出し
│   │   ├── pipeline/                # 並列処理パイプライン
│   │   │   ├── pipeline.ex              # バッチ処理オーケストレーター
│   │   │   └── resource_monitor.ex      # CPU/メモリ検出・動的並列度
│   │   ├── accounts/                # 認証・ユーザー管理
│   │   │   ├── user.ex                  # User スキーマ
│   │   │   ├── user_token.ex            # セッショントークン
│   │   │   ├── user_notifier.ex         # メール通知
│   │   │   └── scope.ex                 # 認証スコープ
│   │   ├── iiif/
│   │   │   └── manifest.ex             # IIIF Manifest スキーマ
│   │   ├── accounts.ex              # 認証コンテキスト
│   │   ├── ingestion.ex               # 取り込みコンテキスト
│   │   ├── search.ex                  # 検索コンテキスト
│   │   └── release.ex                # 本番マイグレーション
│   ├── mix/tasks/
│   │   └── review_summary.ex          # mix review PASS サマリー
│   └── omni_archive_web/
│       ├── components/
│       │   ├── core_components.ex       # Phoenix 標準コンポーネント
│       │   └── wizard_components.ex     # 共通ウィザードコンポーネント
│       ├── live/
│       │   ├── lab_live/                 # Lab プロジェクト管理
│       │   │   ├── index.ex                 # プロジェクト一覧
│       │   │   └── show.ex                  # プロジェクト詳細（画像グリッド）
│       │   ├── inspector_live/          # Lab ウィザード LiveView（全5ステップ）
│       │   │   ├── upload.ex                # Step 1: アップロード
│       │   │   ├── browse.ex                # Step 2: ページ選択
│       │   │   ├── crop.ex                  # Step 3: クロップ
│       │   │   ├── label.ex                 # Step 4: ラベリング
│       │   │   └── finalize.ex              # Step 5: レビュー提出
│       │   ├── search_live.ex           # 検索 LiveView
│       │   ├── approval_live.ex         # 承認 LiveView
│       │   ├── gallery_live.ex          # 公開ギャラリー LiveView
│       │   └── admin/
│       │       ├── review_live.ex       # 管理者レビュー LiveView
│       │       └── admin_trash_live/
│       │           └── index.ex         # ゴミ箱管理 LiveView
│       └── controllers/iiif/           # IIIF API
│           ├── image_controller.ex      # Image API v3.0
│           ├── manifest_controller.ex   # Presentation API v3.0 (個別画像)
│           └── presentation_controller.ex # Presentation API v3.0 (PdfSource 単位)
├── assets/css/
│   ├── admin-review.css                # 管理者レビュー専用テーマ
│   ├── app.css                         # メインスタイル（Tailwind @import）
│   ├── inspector.css                    # ウィザード・クロップ専用スタイル
│   └── lab.css                          # Lab プロジェクト管理スタイル
├── assets/js/hooks/
│   └── image_selection_hook.js         # クロップ選択 JS Hook
├── priv/repo/migrations/              # DB マイグレーション
├── test/                              # テストコード
├── .credo.exs                        # Credo 静的解析設定
├── .sobelow-conf                     # Sobelow セキュリティ設定
├── .dialyzer_ignore.exs              # Dialyzer 既知警告除外
├── Dockerfile                         # マルチステージビルド
├── IIIF_SPEC.md                      # 仕様書
├── ARCHITECTURE.md                   # アーキテクチャ設計
├── DEPLOYMENT.md                     # デプロイ手順書
└── CONTRIBUTING.md                   # 開発参加ガイドライン
```

---

## 📄 ドキュメント

| ドキュメント | 内容 |
|:---|:---|
| [IIIF_SPEC.md](IIIF_SPEC.md) | 開発仕様書 |
| [ARCHITECTURE.md](ARCHITECTURE.md) | アーキテクチャ設計 |
| [DEPLOYMENT.md](DEPLOYMENT.md) | デプロイ手順書 |
| [CONTRIBUTING.md](CONTRIBUTING.md) | 開発参加ガイドライン |
| [CHANGELOG.md](CHANGELOG.md) | 変更履歴 |

---

## 📜 ライセンス

MIT License — 詳細は [LICENSE](LICENSE) を参照してください。

---

## 🙏 謝辞

- [IIIF (International Image Interoperability Framework)](https://iiif.io/)
- [Phoenix Framework](https://www.phoenixframework.org/)
- [vix (libvips Elixir wrapper)](https://github.com/akash-akya/vix)
