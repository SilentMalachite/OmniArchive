# Deployment Guide / デプロイ手順書

This guide covers how to deploy OmniArchive to a production server using Docker,
Docker Compose, or a direct OTP release build. All three approaches require the
same set of environment variables described in Section 1.

OmniArchive のデプロイ方法を説明します。Docker・Docker Compose・OTP リリースビルドの
3つのアプローチに対応しています。いずれも Section 1 の環境変数設定が必要です。

---

## Table of Contents / 目次

1. [Required Environment Variables / 必須環境変数](#1-required-environment-variables--必須環境変数)
2. [Docker Deployment / Docker デプロイ](#2-docker-deployment--docker-デプロイ)
3. [Docker Compose Deployment / Docker Compose デプロイ](#3-docker-compose-deployment--docker-compose-デプロイ)
4. [Local Release Build / ローカルリリースビルド](#4-local-release-build--ローカルリリースビルド)
5. [Database Migrations / データベースマイグレーション](#5-database-migrations--データベースマイグレーション)
6. [Health Check / ヘルスチェック](#6-health-check--ヘルスチェック)
7. [Troubleshooting / トラブルシューティング](#7-troubleshooting--トラブルシューティング)

---

## 1. Required Environment Variables / 必須環境変数

Set the following environment variables before starting the application.
Variables marked ✅ are required; the rest are optional with defaults.

アプリケーションを起動する前に以下の環境変数を設定してください。
✅ は必須項目です。

| Variable / 変数名 | Required / 必須 | Description / 説明 | Example / 例 |
|:---|:---:|:---|:---|
| `DATABASE_URL` | ✅ | PostgreSQL connection URL / PostgreSQL 接続 URL | `ecto://user:pass@localhost/omni_archive_prod` |
| `SECRET_KEY_BASE` | ✅ | Session encryption key (64+ chars) / セッション暗号化キー (64文字以上) | Generate with `mix phx.gen.secret` |
| `PHX_HOST` | ✅ | Production hostname / 本番ホスト名 | `iiif.example.com` |
| `PORT` | | HTTP port / HTTP ポート番号 | `4000` (default) |
| `POOL_SIZE` | | DB connection pool size / DB コネクションプール数 | `10` (default) |
| `ECTO_IPV6` | | Enable IPv6 connections / IPv6 接続を有効化 | `true` |

### Generating SECRET_KEY_BASE

```bash
mix phx.gen.secret
```

---

## 2. Docker Deployment / Docker デプロイ

OmniArchive ships with a multi-stage Dockerfile. Use named volumes to persist
uploads, IIIF tile cache, and PTIF image files across container restarts.

マルチステージ Dockerfile が含まれています。アップロード・キャッシュ・PTIF 画像は
名前付きボリュームで永続化してください。

### Prerequisites / 前提条件

- Docker 20.10 以上

### Build / ビルド

```bash
docker build -t omni_archive .
```

### Start / 起動

```bash
docker run -d \
  --name omni_archive \
  -p 4000:4000 \
  -e DATABASE_URL="ecto://user:pass@host/omni_archive_prod" \
  -e SECRET_KEY_BASE="your_secret_key_base_here" \
  -e PHX_HOST="your-domain.com" \
  -v omni_archive_uploads:/app/priv/static/uploads \
  -v omni_archive_cache:/app/priv/static/iiif_cache \
  -v omni_archive_images:/app/priv/static/iiif_images \
  omni_archive
```

> **⚠️ Important / 重要**: Always mount uploads, cache, and PTIF image directories
> as named volumes. Data in these directories will be lost if the container is removed
> without volumes.
>
> アップロードデータ、キャッシュ、PTIF 画像は永続ボリュームにマウントしてください。
> コンテナを削除するとデータが失われます。

> **Security note / セキュリティ注意**: `priv/static/uploads` is intentionally not
> exposed by Phoenix static file serving. Do not map it directly from a reverse proxy.
> Lab page images must be served through `/lab/uploads/pages/:pdf_source_id/:filename`,
> which performs authentication and owner/admin checks.
>
> `priv/static/uploads` は Phoenix の静的配信対象外です。reverse proxy から直接公開しないでください。
> Lab のページ画像は、認証と所有者/admin 確認を行う
> `/lab/uploads/pages/:pdf_source_id/:filename` 経由でのみ配信します。

### Migration / マイグレーション

```bash
docker exec omni_archive /app/bin/migrate
```

---

## 3. Docker Compose Deployment / Docker Compose デプロイ

Docker Compose starts both the application and a PostgreSQL 15 container together.
A health check ensures the database is ready before the application starts.

Docker Compose を使うと、アプリケーションと PostgreSQL 15 をまとめて起動できます。
ヘルスチェックにより、DB の準備が整ってからアプリケーションが起動します。

```yaml
version: "3.8"

services:
  app:
    build: .
    ports:
      - "4000:4000"
    environment:
      DATABASE_URL: ecto://postgres:postgres@db/omni_archive_prod
      SECRET_KEY_BASE: ${SECRET_KEY_BASE}
      PHX_HOST: ${PHX_HOST:-localhost}
    volumes:
      - uploads:/app/priv/static/uploads
      - cache:/app/priv/static/iiif_cache
      - images:/app/priv/static/iiif_images
    depends_on:
      db:
        condition: service_healthy

  db:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: omni_archive_prod
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  pgdata:
  uploads:
  cache:
  images:
```

```bash
# Generate and export SECRET_KEY_BASE / SECRET_KEY_BASE を生成・設定
export SECRET_KEY_BASE=$(mix phx.gen.secret)

# Start all services / 起動
docker compose up -d

# Run migrations / マイグレーション
docker compose exec app /app/bin/migrate
```

---

## 4. Local Release Build / ローカルリリースビルド

Use this approach if you prefer to run OmniArchive without Docker, directly on
the server OS.

Docker を使わずにサーバー OS 上で直接実行する場合はこの方法を使用してください。

### Prerequisites / 前提条件

- Elixir 1.15+
- Erlang/OTP 24+
- PostgreSQL 15+
- libvips
- poppler-utils
- Node.js / npm

### Build Steps / ビルド手順

```bash
# 1. 依存パッケージを取得
MIX_ENV=prod mix deps.get

# 2. npm 依存をインストール
cd assets && npm install && cd ..

# 3. アセットをコンパイル
MIX_ENV=prod mix assets.deploy

# 4. リリースをビルド
MIX_ENV=prod mix release
```

### Start / 起動

```bash
# 環境変数を設定
export DATABASE_URL="ecto://user:pass@localhost/omni_archive_prod"
export SECRET_KEY_BASE="$(mix phx.gen.secret)"
export PHX_HOST="localhost"

# マイグレーション
_build/prod/rel/omni_archive/bin/migrate

# サーバー起動
_build/prod/rel/omni_archive/bin/server
```

---

## 5. Database Migrations / データベースマイグレーション

Run migrations before starting the application for the first time, and after
each deployment that includes new migration files.

初回起動前と、マイグレーションファイルを含むデプロイの後に実行してください。

### Development / 開発環境

```bash
mix ecto.migrate
```

### Production (Release) / 本番環境 (リリース)

```bash
# Via migration script / 起動スクリプト経由
bin/migrate

# Via Elixir eval / Elixir コード経由
bin/omni_archive eval "OmniArchive.Release.migrate()"
```

### Rollback / ロールバック

```bash
# Development / 開発環境
mix ecto.rollback

# Production / 本番環境
bin/omni_archive eval "OmniArchive.Release.rollback(OmniArchive.Repo, 20260208030921)"
```

---

## 6. Health Check / ヘルスチェック

OmniArchive exposes a health check endpoint at `/api/health`. This is also used
by the Docker `HEALTHCHECK` instruction.

アプリケーションの稼働状態を確認するエンドポイントです。Docker の `HEALTHCHECK` でも使用されます。

```bash
curl http://localhost:4000/api/health
```

Expected response / レスポンス例：

```json
{"status": "ok", "app": "omni_archive"}
```

---

## 7. Troubleshooting / トラブルシューティング

### DB Connection Error / DB 接続エラー

```
** (Postgrex.Error) FATAL role "postgres" does not exist
```

**Fix**: Update the `username` in `config/dev.exs` to match your local PostgreSQL
setup.

**解決策**: `config/dev.exs` の `username` を環境に合わせて変更してください。

### libvips Not Found / libvips が見つからない

```
** (UndefinedFunctionError) Vix.Vips.Image...
```

**Fix**: Install libvips.

**解決策**: libvips をインストールしてください。

```bash
# macOS
brew install vips

# Ubuntu
sudo apt install libvips-dev
```

### pdftoppm Not Found / pdftoppm が見つからない

```
** (ErlangError) :enoent
```

**Fix**: Install poppler-utils.

**解決策**: poppler-utils をインストールしてください。

```bash
# macOS
brew install poppler

# Ubuntu
sudo apt install poppler-utils
```

### Asset Build Errors / アセットビルドエラー

```bash
# Re-install esbuild / esbuild を再インストール
mix esbuild.install --if-missing

# Re-install npm dependencies / npm 依存を再インストール
cd assets && rm -rf node_modules && npm install && cd ..
```
