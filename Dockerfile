# AlchemIIIF Dockerfile
# マルチステージビルド: Elixir + Node.js → Debian slim + libvips + poppler-utils

# ===== ビルドステージ =====
ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28
ARG DEBIAN_VERSION=bookworm-20250113-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# ビルド用パッケージのインストール
RUN apt-get update -y && apt-get install -y \
    build-essential \
    git \
    curl \
    nodejs \
    npm \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

# hex と rebar のインストール
RUN mix local.hex --force && \
    mix local.rebar --force

# 本番環境として設定
ENV MIX_ENV="prod"

# 依存関係のキャッシュ
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# config/の本番用ファイルをコピー
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# ソースコードのコピー
COPY priv priv
COPY lib lib
COPY assets assets

# npm 依存のインストール (cropperjs)
RUN cd assets && npm install

# アプリケーションのコンパイル
# ※ Phoenix 1.8 の colocated hooks を使用するため、
#   assets.deploy の前に compile が必要
RUN mix compile

# アセットのデプロイ
RUN mix assets.deploy

# runtime.exs をコピー
COPY config/runtime.exs config/

# リリースの生成
COPY rel rel
RUN mix release

# ===== ランタイムステージ =====
FROM ${RUNNER_IMAGE}

# ランタイム依存パッケージのインストール
# libvips: IIIF Image API のタイル処理
# poppler-utils: pdftoppm による PDF→PNG 変換
RUN apt-get update -y && \
    apt-get install -y \
    libstdc++6 \
    openssl \
    libncurses5 \
    locales \
    ca-certificates \
    libvips \
    poppler-utils \
    wget \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# ロケール設定
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
RUN sed -i '/ja_JP.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR /app

# 実行ユーザーの作成（セキュリティ）
RUN groupadd --system app && useradd --system --gid app app

# アップロード・キャッシュ用ディレクトリ
RUN mkdir -p /app/priv/static/uploads && \
    mkdir -p /app/priv/static/iiif_cache && \
    mkdir -p /app/priv/static/iiif_images && \
    chown -R app:app /app

# リリースをコピー
COPY --from=builder --chown=app:app /app/_build/prod/rel/alchem_iiif ./

USER app

# ヘルスチェック
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:${PORT:-4000}/api/health || exit 1

CMD ["/app/bin/server"]
