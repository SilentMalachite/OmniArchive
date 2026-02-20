# デプロイ手順書

AlchemIIIF のデプロイ方法を説明します。

---

## 目次

1. [必須環境変数](#必須環境変数)
2. [Docker デプロイ](#docker-デプロイ)
3. [Docker Compose デプロイ](#docker-compose-デプロイ)
4. [ローカルリリースビルド](#ローカルリリースビルド)
5. [データベースマイグレーション](#データベースマイグレーション)
6. [ヘルスチェック](#ヘルスチェック)
7. [トラブルシューティング](#トラブルシューティング)

---

## 必須環境変数

| 変数名 | 必須 | 説明 | 例 |
|:---|:---:|:---|:---|
| `DATABASE_URL` | ✅ | PostgreSQL 接続 URL | `ecto://user:pass@localhost/alchem_iiif_prod` |
| `SECRET_KEY_BASE` | ✅ | セッション暗号化キー (64文字以上) | `mix phx.gen.secret` で生成 |
| `PHX_HOST` | ✅ | 本番ホスト名 | `iiif.example.com` |
| `PORT` | | HTTP ポート番号 | `4000` (デフォルト) |
| `POOL_SIZE` | | DB コネクションプール数 | `10` (デフォルト) |
| `ECTO_IPV6` | | IPv6 接続を有効化 | `true` |

### SECRET_KEY_BASE の生成

```bash
mix phx.gen.secret
```

---

## Docker デプロイ

### 前提条件

- Docker 20.10 以上

### ビルド

```bash
docker build -t alchem_iiif .
```

### 起動

```bash
docker run -d \
  --name alchem_iiif \
  -p 4000:4000 \
  -e DATABASE_URL="ecto://user:pass@host/alchem_iiif_prod" \
  -e SECRET_KEY_BASE="your_secret_key_base_here" \
  -e PHX_HOST="your-domain.com" \
  -v alchem_iiif_uploads:/app/priv/static/uploads \
  -v alchem_iiif_cache:/app/priv/static/iiif_cache \
  -v alchem_iiif_images:/app/priv/static/iiif_images \
  alchem_iiif
```

> **⚠️ 重要**: アップロードデータ、キャッシュ、PTIF 画像は永続ボリュームにマウントしてください。
> コンテナを削除するとデータが失われます。

### マイグレーション

```bash
docker exec alchem_iiif /app/bin/migrate
```

---

## Docker Compose デプロイ

以下の `docker-compose.yml` を使用できます：

```yaml
version: "3.8"

services:
  app:
    build: .
    ports:
      - "4000:4000"
    environment:
      DATABASE_URL: ecto://postgres:postgres@db/alchem_iiif_prod
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
      POSTGRES_DB: alchem_iiif_prod
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
# SECRET_KEY_BASE を設定
export SECRET_KEY_BASE=$(mix phx.gen.secret)

# 起動
docker compose up -d

# マイグレーション
docker compose exec app /app/bin/migrate
```

---

## ローカルリリースビルド

Docker を使わずに直接リリースビルドを行う場合：

### 前提条件

- Elixir 1.15+
- Erlang/OTP 24+
- PostgreSQL 15+
- libvips
- poppler-utils
- Node.js / npm

### ビルド手順

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

### 起動

```bash
# 環境変数を設定
export DATABASE_URL="ecto://user:pass@localhost/alchem_iiif_prod"
export SECRET_KEY_BASE="$(mix phx.gen.secret)"
export PHX_HOST="localhost"

# マイグレーション
_build/prod/rel/alchem_iiif/bin/migrate

# サーバー起動
_build/prod/rel/alchem_iiif/bin/server
```

---

## データベースマイグレーション

### 開発環境

```bash
mix ecto.migrate
```

### 本番環境 (リリース)

```bash
# 起動スクリプト経由
bin/migrate

# または Elixir コード経由
bin/alchem_iiif eval "AlchemIiif.Release.migrate()"
```

### ロールバック

```bash
# 開発環境
mix ecto.rollback

# 本番環境
bin/alchem_iiif eval "AlchemIiif.Release.rollback(AlchemIiif.Repo, 20260208030921)"
```

---

## ヘルスチェック

アプリケーションの稼働状態を確認するエンドポイント：

```bash
curl http://localhost:4000/api/health
```

レスポンス例：

```json
{"status": "ok", "app": "alchem_iiif"}
```

Docker の HEALTHCHECK でも使用されています。

---

## トラブルシューティング

### DB 接続エラー

```
** (Postgrex.Error) FATAL role "postgres" does not exist
```

**解決策**: `config/dev.exs` の `username` を環境に合わせて変更してください。

### libvips が見つからない

```
** (UndefinedFunctionError) Vix.Vips.Image...
```

**解決策**: libvips をインストールしてください。

```bash
# macOS
brew install vips

# Ubuntu
sudo apt install libvips-dev
```

### pdftoppm が見つからない

```
** (ErlangError) :enoent
```

**解決策**: poppler-utils をインストールしてください。

```bash
# macOS
brew install poppler

# Ubuntu
sudo apt install poppler-utils
```

### アセットビルドエラー

```bash
# esbuild を再インストール
mix esbuild.install --if-missing

# npm 依存を再インストール
cd assets && rm -rf node_modules && npm install && cd ..
```
