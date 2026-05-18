# OmniArchive

[![CI](https://github.com/SilentMalachite/OmniArchive/actions/workflows/ci.yml/badge.svg)](https://github.com/SilentMalachite/OmniArchive/actions/workflows/ci.yml)
[![Elixir](https://img.shields.io/badge/Elixir-1.15+-4B275F?logo=elixir)](https://elixir-lang.org/)
[![Phoenix](https://img.shields.io/badge/Phoenix-1.8+-E85629?logo=phoenix-framework)](https://www.phoenixframework.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15+-4169E1?logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![IIIF](https://img.shields.io/badge/IIIF-v3.0-2873AB)](https://iiif.io/)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

**Convert static PDFs (and PNG ZIPs) into IIIF v3-compliant digital archives.**

静的な PDF（および PNG の ZIP）を IIIF v3 準拠のデジタルアーカイブに変換する Web アプリケーションです。

---

## Background / 背景

OmniArchive originated in a supported employment context (就労継続支援) in Niigata, Japan. Many historical documents — excavation reports, regional archive materials, library holdings — exist only as static PDFs and are therefore inaccessible to standard digital-archive tools. OmniArchive targets small institutions (local museums, regional archives, libraries) that want IIIF-compliant workflows without dedicated digital-archive staff.

Cognitive accessibility is a first-class design constraint: the project was built by and for people who work in accessibility-conscious environments.

OmniArchive は新潟県の就労継続支援 B 型施設の現場から生まれたプロジェクトです。静的 PDF としてしか存在しない歴史資料を、専任スタッフを持たない小規模機関でも IIIF 準拠のデジタルアーカイブとして公開できるようにすることを目指しています。認知アクセシビリティを設計の根幹に据えています。

---

## What it does / 何ができるか

- Upload a PDF (or a ZIP of PNG pages) → pages are converted to high-resolution images
- Pick figures, crop them with a polygon tool, and attach metadata
- A review workflow ensures quality before publication
- Approved images are published as IIIF v3 Manifests, viewable in any IIIF-compatible viewer (Mirador, Universal Viewer, OpenSeadragon)

PDF または PNG の ZIP をアップロード → 高解像度画像に変換 → 多角形クロップでメタデータを付与 → 管理者の承認を経て IIIF v3 Manifest として公開します。

![Lab Wizard Interface](priv/static/images/wizard.jpg)
![Gallery Interface](priv/static/images/gallery.jpg)

---

## Who is this for / 想定ユーザー

- **Small archives and local governments** that want to publish historical materials as interoperable digital archives without vendor lock-in
- **Supported employment facilities** (就労継続支援) looking for structured, meaningful work for people with disabilities
- **IIIF developers and cultural-heritage technologists** interested in a real-world Elixir/Phoenix implementation
- **Domain practitioners** (libraries, museums, archaeology) who need a customizable metadata schema via YAML profiles

---

## Quick Start / クイックスタート

```bash
# 1. Clone
git clone https://github.com/SilentMalachite/OmniArchive.git
cd OmniArchive

# 2. Install dependencies and set up the database
mix setup

# 3. Start the server
mix phx.server
```

Open <http://localhost:4000/lab> in your browser.

**Default accounts** (seeded by `mix ecto.setup`):

| Role  | Email | Password |
|-------|-------|----------|
| Admin | `admin@example.com` | `Password1234!` |
| User  | `user@example.com`  | `Password1234!` |

Prerequisites: Elixir 1.15+, Erlang/OTP 24+, PostgreSQL 15+, libvips, poppler-utils, Node.js. For platform-specific install commands and production setup, see [DEPLOYMENT.md](DEPLOYMENT.md).

前提パッケージ: Elixir 1.15+, Erlang/OTP 24+, PostgreSQL 15+, libvips, poppler-utils, Node.js。OS 別のインストール手順や本番デプロイは [DEPLOYMENT.md](DEPLOYMENT.md) を参照してください。

---

## Documentation / ドキュメント

### For users / 一般利用者向け

| Document | Description |
|----------|-------------|
| [USER_GUIDE.md](USER_GUIDE.md) | How to use the Lab wizard, Gallery, and admin review workflow. Includes FAQ and troubleshooting. / Lab ウィザード・Gallery・管理者ワークフローの使い方と FAQ |

### For developers / 開発者向け

| Document | Description |
|----------|-------------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Modular-monolith design, OTP pipeline, Stage-Gate model / アーキテクチャ設計 |
| [IIIF_SPEC.md](IIIF_SPEC.md) | IIIF Image API v3.0 and Presentation API v3.0 implementation / IIIF 実装仕様 |
| [PROFILES.md](PROFILES.md) | YAML-driven domain profiles (metadata, validation, facets) / ドメインプロファイル定義 |
| [DEPLOYMENT.md](DEPLOYMENT.md) | Docker, Docker Compose, and OTP release deployment / デプロイ手順 |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Branch strategy, coding standards, accessibility checklist / 貢献ガイド |
| [AGENTS.md](AGENTS.md) | Repository-level rules and validation gate / リポジトリ運用ルール |
| [CHANGELOG.md](CHANGELOG.md) | Release history / リリース履歴 |

---

## Tech Stack / 技術スタック

| | |
|---|---|
| Language / Framework | Elixir 1.15+ / Phoenix 1.8+ (LiveView) |
| Database | PostgreSQL 15+ (JSONB metadata, tsvector + GIN full-text search) |
| Image processing | [vix](https://github.com/akash-akya/vix) (libvips), Pyramidal TIFF |
| PDF conversion | [poppler-utils](https://poppler.freedesktop.org/) (`pdftoppm`) |
| Frontend | Phoenix LiveView + a custom `ImageSelection` JS Hook for polygon cropping |
| Container | Multi-stage Dockerfile |

---

## Domain profiles / ドメインプロファイル

Metadata fields, validation rules, search facets, and UI labels are **not hardcoded**. They live in pluggable domain profiles. Built-in: `GeneralArchive` (default), `Archaeology`. A YAML-defined profile activates when `OMNI_ARCHIVE_PROFILE_YAML` points to a YAML file. See [PROFILES.md](PROFILES.md).

メタデータ・バリデーション・ファセット・UI 文言は共通モジュールに直書きせず、ドメインプロファイルに集約します。組み込み: `GeneralArchive`（既定）／`Archaeology`。YAML プロファイルは `OMNI_ARCHIVE_PROFILE_YAML` で切り替えます。詳細は [PROFILES.md](PROFILES.md)。

---

## License / ライセンス

Released under the **Apache License 2.0** — see [LICENSE](LICENSE) for details. Apache 2.0 includes patent clauses, making it suitable for deployment at public institutions and academic organizations.

**Apache License 2.0** で公開しています。公共機関・学術機関でのデプロイにも適合します。

---

## Acknowledgements / 謝辞

- [IIIF Consortium](https://iiif.io/) — for the open standard that makes interoperable digital archives possible
- [Phoenix Framework](https://www.phoenixframework.org/)
- [vix (libvips Elixir wrapper)](https://github.com/akash-akya/vix)

OmniArchive is a domain-agnostic successor to [AlchemIIIF](https://github.com/SilentMalachite/AlchemIIIF), which was built for archaeological site reports.

OmniArchive は考古学報告書向けに開発した [AlchemIIIF](https://github.com/SilentMalachite/AlchemIIIF) の汎用版です。
