# OmniArchive

[![CI](https://github.com/SilentMalachite/OmniArchive/actions/workflows/ci.yml/badge.svg)](https://github.com/SilentMalachite/OmniArchive/actions/workflows/ci.yml)
[![Elixir](https://img.shields.io/badge/Elixir-1.15+-4B275F?logo=elixir)](https://elixir-lang.org/)
[![Phoenix](https://img.shields.io/badge/Phoenix-1.8+-E8562A?logo=phoenix-framework)](https://www.phoenixframework.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15+-4169E1?logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![IIIF](https://img.shields.io/badge/IIIF-v3.0-2873AB)](https://iiif.io/)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

> **Convert static PDFs into IIIF (International Image Interoperability Framework)-compliant digital assets.**
>
> **静的な PDF を、IIIF (International Image Interoperability Framework) に準拠したリッチなデジタルアセットに変換するツールです。**

OmniArchive is an Elixir/Phoenix application that transforms static PDF documents into
IIIF-compliant digital archives. It supports multiple domain profiles through YAML-driven
configuration, making it suitable for archaeological reports, library materials, museum
collections, and other archival use cases.

OmniArchive は、静的な PDF を IIIF に準拠したデジタルアーカイブに変換する Elixir/Phoenix アプリケーションです。
YAML 設定によるドメインプロファイルの切り替えにより、考古学報告書・図書館資料・博物館コレクションなど、
さまざまなアーカイブ用途に対応します。

---

## Background / プロジェクトの背景

OmniArchive originated in a supported employment context (就労継続支援) in Niigata, Japan.
The primary use case is digitizing historical documents — excavation reports, local archive
materials — that exist only as static PDFs and are therefore inaccessible to standard digital
archive tools. It targets small institutions such as local museums and regional archives that
want to adopt IIIF-compliant workflows without dedicated digital archive staff. Cognitive
accessibility is a first-class design constraint, not an afterthought: the project was built
by and for people who work in accessibility-conscious environments.

> OmniArchive は、新潟県の就労継続支援 B 型施設の現場から生まれたプロジェクトです。
> 主な用途は、静的 PDF としてしか存在しない歴史資料（発掘調査報告書・地域アーカイブ素材）のデジタル化です。
> 専任スタッフのいない小規模機関（地方博物館・地域アーカイブなど）が、IIIF に準拠したデジタルアーカイブを
> 自前で構築できるようにすることを目指しています。認知アクセシビリティを設計の根幹に置いており、
> アクセシビリティを意識した環境で働く人々によって、その人々のために開発されました。

---

## ✨ Key Features / 主な特徴

### 🧙 Wizard-based Inspector (Lab) / ウィザード型インスペクタ (Lab)

The Lab workspace guides users through a **5-step wizard** to create IIIF assets from a PDF.
Each step is designed for clarity and cognitive accessibility.

直感的な **5 ステップ**のウィザード形式で、PDF から IIIF アセットを作成します。

![Lab Wizard Interface](priv/static/images/wizard.jpg)

| ステップ | アイコン | 内容 |
|:---:|:---:|:---|
| **1. アップロード** | 📄 | PDF をアップロードすると、10 ページ単位のチャンク分割で全ページが高解像度 PNG に変換されます。変換モード（🖤 モノクロ / 🎨 カラー）を選択可能。「要修正」タブで差し戻された図版の修正も可能です |
| **2. ページ選択** | 🔍 | サムネイルグリッドから図版を含むページを選択します（レコードは未作成 — Write-on-Action） |
| **3. クロップ** | ✂️ | オリジナルの JS Hook を使用。クリックで頂点を追加し多角形（ポリゴン）を描画。**ダブルクリック（または始点クリック / Enter）**で確定・保存（ここで初めてレコード作成） |
| **4. ラベリング** | 🏷️ | メタデータを入力します。入力内容はリアルタイムで保存されます。 |
| **5. レビュー提出** | ✅ | 内容を確認し、レビュー依頼を提出します。管理者が承認すると、自動的に公開用 PTIF が生成されます |

### 🏛️ Stage-Gate Workflow (Lab → Gallery) / Stage-Gate ワークフロー (Lab → Gallery)

OmniArchive separates internal work from public publishing to ensure quality control.
Reviewers approve or return items before they appear in the public Gallery.

品質管理のため、内部作業と公開を明確に分離しています。

| ステージ | 説明 |
|:---:|:---|
| **Lab (内部)** | プロジェクト一覧（`/lab`）から PDF を選択し、アップロード・クロップ・ラベリングを行う内部ワークスペース |
| **プロジェクトワークフロー** | プロジェクト単位の作業進捗管理（作業中 → 審査待ち → 差し戻し/承認）。一般ユーザーが「作業完了」として提出し、管理者が承認または差し戻し（メッセージ付き）を行います |
| **承認** | 管理者が `/admin/review` で内容を確認、承認、差し戻し、または削除（一括削除対応）を行います |
| **差し戻し・再提出** | 差し戻されたアセットは「要修正」タブに表示され、修正後に再提出できます。プロジェクトレベル・画像レベル両方の差し戻し理由を確認可能です |
| **Gallery (公開)** | 承認されたアセットを表示。カードクリックで IIIF 対応の OpenSeadragon 拡大モーダル（PTIFF 生成前は SVG ベースのフォールバック）を表示します。高解像度クロップ画像のダウンロードも可能です |
| **管理者ダッシュボード** | 管理者が `/admin` で全ユーザーのデータを管理。非同期ロードによる高速表示。一括削除やユーザー管理が可能です |
| **ゴミ箱管理** | 削除されたプロジェクトは `/admin/trash` で管理。復元または完全削除が可能です。公開済プロジェクトは削除から保護されます |

### 🔍 Search and Discovery / 検索・発見

OmniArchive provides full-text search powered by PostgreSQL FTS (full-text search) and
faceted filtering based on domain profile metadata fields.

![Gallery Interface](priv/static/images/gallery.jpg)

- **全文検索**: キャプションの PostgreSQL FTS (tsvector + GIN インデックス)
- **ファセット検索**: active profile で定義されたメタデータ項目によるフィルタリング

利用可能な profile:
- `OmniArchive.DomainProfiles.Archaeology` (デフォルト)
- `OmniArchive.DomainProfiles.GeneralArchive`
- **YAML 定義プロファイル** (v0.2.23 以降): `OMNI_ARCHIVE_PROFILE_YAML` 環境変数で YAML ファイルを指定

切り替え方法:
- **組み込みプロファイル**: `config/config.exs` の `config :omni_archive, domain_profile: ...` で指定
- **YAML プロファイル**: 環境変数 `OMNI_ARCHIVE_PROFILE_YAML=/path/to/profile.yaml` を設定して起動（自動的に `OmniArchive.DomainProfiles.Yaml` が有効になります）

詳細は [PROFILES.md](PROFILES.md) を参照してください。

### ♿ Cognitive Accessibility / 認知アクセシビリティ

Accessibility is a core design principle, not an add-on. Every interface element is
designed to reduce cognitive load and support users who may find complex workflows difficult.

- **ギャラリー & 管理画面テーマ**: 「新潟インディゴ＆ハーベストゴールド」— Deep Sea Indigo (#1A2C42) 背景 + Harvest Gold (#E6B422) アクセント、Mist Grey (#E0E0E0) テキストでコントラスト比約 10.4:1（WCAG AAA 準拠）。公開ギャラリーに加え、管理者レビュー画面にも適用されています。
- **線形フロー**: ウィザードパターンで迷わない操作
- **D-Pad ナッジコントロール**: 3×3 Grid 配置の方向ボタンによるポリゴン全体の微調整（精密なドラッグ操作が不要）。物理コントローラーを意識した D-Pad レイアウト。
- **大きなボタン**: 全ての操作ボタンは D-Pad を含め最小 60×60px（主要ボタンは 64×64px）
- **即時フィードバック**: 明確な成功・エラーメッセージ
- **手動入力**: AI による自動抽出は行わず、全ての選択は人が行います

### 🔒 Authentication and Access Control / 認証システム & 権限管理

OmniArchive uses role-based access control (RBAC) with `admin` and `user` roles.
Each user can only access their own projects; administrators have full visibility.

- **ロールベースアクセス制御 (RBAC)**: `admin` と `user` ロールによる権限管理。
- **プロジェクトの所有権分離 (User Scoping)**: `PdfSource` は「所有者 (`user_id`)」を持ちます。管理者は全データにアクセスできますが、一般ユーザーは自身がアップロードしたプロジェクト（およびその中の画像）のみ閲覧・編集が可能なように堅牢にスコープされます。他人のプロジェクトへはアクセスできません。
- **セッションベース認証**: `phx.gen.auth` によるセッション管理。Lab と Admin はログイン必須です
- **招待制モデル**: 公開ユーザー登録を制限し、管理者によるアカウント作成・招待モデルを採用しています
- **グローバルナビバー**: ログイン状態に応じたナビゲーション。管理者には管理メニューが表示されます
- **複数ユーザーの協力モデル**: `ExtractedImage` にも `owner_id` / `worker_id` の追跡を持たせ、管理者が全体の作業状況を把握できます。

### 🛡️ Data Integrity and Reliability / データ整合性と信頼性

OmniArchive enforces strict validation at every stage to guarantee the quality and
consistency of bibliographic metadata and image assets.

- **厳格なバリデーション**: ラベル形式 (`fig-1-1`) や自治体名（市町村必須）の強制により、書誌情報の品質を担保
- **ファイルバージョニング**: アップロードファイルへのタイムスタンプ付与により、ブラウザキャッシュの衝突（ゴースト画像）を完全に防止
- **Write-on-Action**: 閲覧操作と保存操作を明確に分離し、意図しない空レコードの作成を防止
- **ソフトデリート**: プロジェクト削除は `deleted_at` タイムスタンプによる論理削除。ゴミ箱からの復元または完全削除が可能
- **公開済みプロジェクト保護**: Gallery に公開済みの画像を含むプロジェクトは削除不可。UI 上でロックアイコンを表示
- **プロジェクト ワークフロー管理**: プロジェクト単位で作業進捗を管理（`wip` → `pending_review` → `returned` / `approved`）。差し戻し時には管理者メッセージを記録可能
- **セキュリティと入力制限**: XSS やリソース枯渇攻撃を防ぐため、メタデータ入力に profile 定義ベースの文字数制限と形式検証を導入。

### ⚡ Parallel Processing Pipeline / 並列処理パイプライン & バックグラウンド処理

OmniArchive uses Elixir's OTP (Open Telecom Platform) concurrency model to process large
PDFs reliably on low-resource servers. Each user gets a dedicated background worker process,
keeping the UI responsive during processing.

- **OTP バックグラウンド処理基盤**: ユーザーごとに専属の `UserWorker` (GenServer) を起動し、PDF 処理を LiveView から分離。`DynamicSupervisor` + `Registry` でプロセスを管理し、PubSub による完了通知で UI を自動更新
- **libvips グローバル制約**: アプリケーション起動時に libvips の並行度を 1 に制限し、キャッシュ上限を設定。VPS 環境でのメモリ使用量を制御
- **PDF チャンク逐次処理**: 大規模 PDF（200+ ページ）を 10 ページ単位に分割して逐次変換。メモリ 2GB の VPS でも OOM を回避
- **PDF カラーモード選択**: Upload 画面で「モノクロ（高速）」と「カラー（標準）」を切替可能。モノクロモードでは `pdftoppm -gray` でグレースケール変換し処理を高速化
- **DB バルクインサート最適化**: `ExtractedImage` の DB 登録を `Repo.insert_all` による一括挿入に移行。DB ラウンドトリップを N 回 → 1 回に削減し、大規模 PDF の処理を高速化
- **Lazy PTIFF 生成**: 編集中の不要な負荷を避けるため、管理者が承認した時点で初めて公開用 PTIFF を生成。リソース消費を最小化
- **DEFLATE 可逆圧縮**: PTIFF 生成に DEFLATE 圧縮を採用。線画や図版に発生しがちなモスキートノイズを完全に防止
- **チャンク進捗プログレスバー**: チャンク完了ごとに PubSub で進捗を配信し、Upload 画面にリアルタイムプログレスバー（ページ数/パーセント表示）を表示
- **リソース適応型並列処理**: CPU コア数・空きメモリを自動検出し、最適な並列度で処理
- **メモリガード**: 空きメモリが 20% 未満になると並列度を自動縮小し、スワップを回避
- **リアルタイム進捗表示**: PubSub によるバッチ処理の進捗をリアルタイムで表示
- **UI レスポンス保証**: 1 CPU コアを常に UI スレッド用に確保

### 🖼️ IIIF v3.0 Compliance / IIIF v3.0 準拠

OmniArchive implements both the IIIF Image API v3.0 and the IIIF Presentation API v3.0.
Manifests are served as JSON-LD and can be loaded directly into standard IIIF viewers
such as Mirador and Universal Viewer.

- **Image API v3.0**: PTIF からの動的タイル生成 + キャッシュ
- **Presentation API v3.0**: JSON-LD 形式の Manifest（英語/日本語対応）
  - **個別画像 Manifest**: `GET /iiif/manifest/:identifier` — 単一画像の Manifest
  - **PdfSource 単位 Manifest**: `GET /iiif/presentation/:source_id/manifest` — 資料内の公開済み画像を Canvas として集約

### 🔒 Quality Pipeline (`mix review`) / 品質チェック (`mix review`)

A single command runs the full quality, security, and type-safety pipeline.

単一コマンドで品質・セキュリティ・型安全性を検証する自動レビューパイプライン：

- **コンパイル**: `--warnings-as-errors` で警告ゼロを保証
- **Credo**: `--strict` モードでコードスタイルを検査
- **Sobelow**: セキュリティ脆弱性の静的解析
- **Dialyzer**: 型レベルの安全性チェック

### 🚀 GitHub Actions CI

`push` (main) / `pull_request` で自動実行される CI パイプライン（`.github/workflows/ci.yml`）：

| ステップ | 内容 |
|:---|:---|
| 環境 | `ubuntu-latest` + PostgreSQL 15 サービスコンテナ |
| 言語 | Elixir `1.18.x` / OTP `27`（`erlef/setup-beam`） |
| キャッシュ | `deps` & `_build` を `mix.lock` ハッシュでキャッシュ |
| 厳格コンパイル | `mix compile --warnings-as-errors` |
| フォーマット | `mix format --check-formatted` |
| テスト | `mix test`（PostgreSQL 接続） |

---


## 🛠️ Technology Stack / 技術スタック

| Category / カテゴリ | Technology / 技術 |
|:---|:---|
| Language / Framework | Elixir 1.15+ / Phoenix 1.8+ (LiveView) |
| Database | PostgreSQL 15+ (JSONB メタデータ) |
| Image Processing | [vix](https://github.com/akash-akya/vix) (libvips ラッパー) |
| PDF Conversion | [poppler-utils](https://poppler.freedesktop.org/) (pdftoppm) |
| Frontend | Phoenix LiveView + 独自の JavaScript Hook (ImageSelection ポリゴン描画) |
| Container | Docker (マルチステージビルド) |

---

## 🚀 Setup / セットアップ

The following instructions cover installation on macOS, Linux, and Windows.
All commands are the same on macOS and Linux unless otherwise noted.

以下の手順で開発環境をセットアップしてください。macOS と Linux では同じコマンドを使用します。

### Prerequisites / 前提条件

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
git clone https://github.com/SilentMalachite/OmniArchive.git
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

### Installation / インストール手順

```bash
# 1. リポジトリをクローン
git clone https://github.com/SilentMalachite/OmniArchive.git
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
> **初回ログイン**: `mix ecto.setup` でデフォルトユーザーが自動作成されます。
> - **管理者**: `admin@example.com` (パスワード: `Password1234!`)
> - **一般**: `user@example.com` (パスワード: `Password1234!`)

---

## 📖 Usage / 使い方

### 1. Upload a PDF / PDF をアップロード

`/lab` にアクセスし、PDF ファイルをアップロードします。
アップロード前に **変換モード** を選択できます：

| モード | 説明 |
|:---:|:---|
| 🖤 **モノクロモード（高速）** | `-gray` フラグ付きでグレースケール変換。線画中心の資料に最適（デフォルト） |
| 🎨 **カラーモード（標準）** | フルカラーで出力。写真や彩色図を含む資料向け |

アップロードされた PDF は自動的に 10 ページ単位でチャンク分割され、300 DPI の PNG 画像に逐次変換されます。

### 2. Select Pages / ページを選択

変換されたページがサムネイルグリッドとして表示されます。
図版や挿絵を含むページをクリックして選択してください。

> **注意**: この段階ではデータベースにレコードは作成されません（Write-on-Action ポリシー）。

### 3. Crop Figures / 図版をクロップ

独自の JavaScript Hook (`ImageSelection`) を使用して、ページ上の図版の範囲を多角形（ポリゴン）で指定します。

- **ポリゴン描画**: クリックで頂点を追加し、ダブルクリック（または始点クリック / Enter キー）で多角形を閉じて保存します。**この操作で初めてレコードが作成されます。**
- **D-Pad ナッジボタン** (↑↓←→): 10px 単位でポリゴン全体を微調整。キーボードの矢印キーでも操作可能です。
- **クリア（やり直し）**: ポリゴンをリセットして最初から描き直すことができます。Undo 機能も利用可能です。

### 4. Add Metadata Labels / ラベリング（メタデータ入力）

キャプション（図の説明）、ラベル（識別名）、および active profile で定義されたメタデータを入力してください。
自動保存機能により、入力値はリアルタイムで保存されます。クロップ範囲が未設定の場合、保存はブロックされます。

### 5. Submit for Review / レビュー提出

確認画面で入力内容を確認し、「保存」を押します。
システムが以下を自動的に行います：

1. クロップ画像の生成
2. ピラミッド型 TIFF (PTIF) への変換
3. IIIF Manifest の登録

### 6. Approve and Publish / 承認・公開

1. `/lab/approval` で作業者がアイテムを「レビュー依頼」として提出します。
2. `/admin/review` で管理者が内容を確認し、承認すると `/gallery` に公開されます。
3. 管理者は必要に応じて、アイテムの一括削除やユーザー管理を行うことができます。

### 7. Search / 検索

`/lab/search` で、profile 定義に含まれるメタデータ項目とキャプションから画像を検索できます。

### IIIF Endpoints / IIIF エンドポイント

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

## 🐳 Docker Deployment / Docker デプロイ

OmniArchive ships with a multi-stage Dockerfile. The commands below start the application
with a PostgreSQL connection.

マルチステージビルドの Dockerfile が含まれています。以下のコマンドでアプリケーションを起動できます。

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

## 📦 OTP Release Build / OTP リリースビルド

Docker を使わずにローカルでリリースビルドを作成できます。

### Prerequisites / 前提条件

- Elixir 1.15+ / Erlang/OTP 24+
- PostgreSQL 15+
- libvips / poppler-utils
- Node.js / npm

### Build Steps / ビルド手順

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

### Start (Linux / macOS)

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

### Start (Windows)

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

## 📁 Directory Structure / ディレクトリ構成

```
OmniArchive/
├── lib/
│   ├── omni_archive/
│   │   ├── ingestion/               # 取り込みパイプライン
│   │   │   ├── pdf_source.ex            # PDF 管理スキーマ
│   │   │   ├── extracted_image.ex       # 抽出画像スキーマ
│   │   │   ├── pdf_processor.ex         # PDF→PNG 変換
│       │   ├── image_processor.ex       # クロップ（矩形・ポリゴン）・PTIF 生成・タイル切り出し
│   │   ├── pipeline/                # 並列処理パイプライン
│   │   │   ├── pipeline.ex              # バッチ処理オーケストレーター
│   │   │   └── resource_monitor.ex      # CPU/メモリ検出・動的並列度
│   │   ├── workers/                 # OTP バックグラウンド処理
│   │   │   └── user_worker.ex           # ユーザー専属 GenServer
│   │   ├── domain_profiles/         # ドメインプロファイル
│   │   │   ├── yaml.ex                  # YAML プロファイルモジュール
│   │   │   ├── yaml_cache.ex            # ETS バック GenServer キャッシュ
│   │   │   └── yaml_loader.ex           # YAML パース・バリデーション
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
│       └── image_selection_hook.js         # ポリゴンクロップ選択 JS Hook
├── priv/profiles/                     # YAML ドメインプロファイル
│   └── example_profile.yaml             # サンプルプロファイル
├── priv/repo/migrations/              # DB マイグレーション
├── test/                              # テストコード
├── .github/workflows/ci.yml         # GitHub Actions CI パイプライン
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

## 📄 Documentation / ドキュメント

| Document / ドキュメント | Description / 内容 |
|:---|:---|
| [IIIF_SPEC.md](IIIF_SPEC.md) | IIIF Image API and Presentation API endpoint specifications / IIIF エンドポイント仕様書 |
| [ARCHITECTURE.md](ARCHITECTURE.md) | System architecture and design decisions / アーキテクチャ設計 |
| [DEPLOYMENT.md](DEPLOYMENT.md) | Server deployment guide (Docker, OTP release) / デプロイ手順書 |
| [PROFILES.md](PROFILES.md) | YAML-based domain profile configuration / YAML ベースのドメインプロファイル定義 |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute to the project / 開発参加ガイドライン |
| [CHANGELOG.md](CHANGELOG.md) | Version history and release notes / 変更履歴 |

---

## 📜 License / ライセンス

Released under the **Apache License 2.0** — see [LICENSE](LICENSE) for details.
Apache 2.0 includes patent clauses that make it suitable for deployment at public institutions and academic organizations.

**Apache License 2.0** で公開しています。詳細は [LICENSE](LICENSE) を参照してください。
Apache 2.0 は特許条項を含むため、公共機関・学術機関でのデプロイに適しています。

---

## 🙏 Acknowledgments / 謝辞

- [IIIF Consortium (International Image Interoperability Framework)](https://iiif.io/) — for the open standard that makes interoperable digital archives possible
- [Phoenix Framework](https://www.phoenixframework.org/)
- [vix (libvips Elixir wrapper)](https://github.com/akash-akya/vix)

OmniArchive is a domain-agnostic successor to [AlchemIIIF](https://github.com/SilentMalachite/AlchemIIIF),
which was built for archaeological site reports. / 考古学報告書向けに開発した AlchemIIIF の汎用版です。
