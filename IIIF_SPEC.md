# IIIF Implementation Specification / IIIF 実装仕様書

OmniArchive implements the IIIF (International Image Interoperability Framework)
Image API v3.0 and Presentation API v3.0. This document describes the endpoint
specifications, Manifest structure, compliance level, and viewer compatibility.

OmniArchive は IIIF Image API v3.0 および Presentation API v3.0 を実装しています。
本ドキュメントでは、エンドポイント仕様・Manifest 構造・準拠レベル・ビューア互換性を記載します。

---

## 1. IIIF Compliance Level / 準拠レベル

### Image API Compliance

OmniArchive targets **Image API Compliance Level 2**.

| Feature | Support |
|:---|:---|
| Full image request (`full`) | ✅ |
| Region by pixel (`x,y,w,h`) | ✅ |
| Size by pixel (`w,`) | ✅ |
| Size `max` | ✅ |
| Rotation `0` | ✅ |
| Rotation `90`, `180`, `270` | ✅ |
| Quality `default`, `color`, `gray` | ✅ |
| Format `jpg`, `png`, `webp` | ✅ |
| `info.json` endpoint | ✅ |

> Compliance level is self-assessed based on implemented features.
> Formal compliance testing against the IIIF compliance suite has not yet been performed.

### Presentation API Compliance

OmniArchive outputs Presentation API v3.0-compliant JSON-LD Manifests, including
the `Canvas`, `AnnotationPage`, and `Annotation` hierarchy required by the specification.
Multilingual labels (`en` / `ja`) are supported.

---

## 2. Endpoints / エンドポイント一覧

### Image API v3.0

```
GET /iiif/image/{identifier}/{region}/{size}/{rotation}/{quality}.{format}
GET /iiif/image/{identifier}/info.json
```

| Parameter | Values | Description |
|:---|:---|:---|
| `identifier` | e.g. `img-42-12345` | Unique image identifier / 画像の一意識別子 |
| `region` | `full`, `square`, `x,y,w,h`, `pct:x,y,w,h` | Region to extract / 切り出し領域 |
| `size` | `max`, `w,`, `,h`, `w,h`, `pct:n` | Output size / 出力サイズ |
| `rotation` | `0`, `90`, `180`, `270` | Rotation in degrees / 回転角度 |
| `quality` | `default`, `color`, `gray` | Image quality / 画質 |
| `format` | `jpg`, `png`, `webp` | Output format / 出力フォーマット |

**`info.json` response example:**

```json
{
  "@context": "http://iiif.io/api/image/3/context.json",
  "id": "https://example.com/iiif/image/img-42-12345",
  "type": "ImageService3",
  "protocol": "http://iiif.io/api/image",
  "width": 4000,
  "height": 3000,
  "profile": "level2",
  "tiles": [
    {
      "width": 256,
      "scaleFactors": [1, 2, 4, 8]
    }
  ]
}
```

### Presentation API v3.0

```
GET /iiif/manifest/{identifier}
GET /iiif/presentation/{source_id}/manifest
```

| Endpoint | Description |
|:---|:---|
| `GET /iiif/manifest/{identifier}` | Single-image Manifest. Backed by the `iiif_manifests` table. Only available for `published` images. |
| `GET /iiif/presentation/{source_id}/manifest` | Source-level Manifest. Aggregates all `published` images under a `PdfSource` as Canvases, ordered by `page_number` ascending. |

---

## 3. Manifest Examples / Manifest 実例

### 3.1 Single-Image Manifest

The following is a representative JSON-LD Manifest for a single cropped figure.
All string values in `label` and `summary` use the IIIF language map format.

単一クロップ図版の JSON-LD Manifest 実例です。
`label` と `summary` はすべて IIIF 言語マップ形式で記述されます。

```json
{
  "@context": "http://iiif.io/api/presentation/3/context.json",

  "id": "https://example.com/iiif/manifest/img-42-12345",
  "type": "Manifest",

  // Multilingual label: English and Japanese
  "label": {
    "en": ["Figure 3: Pottery excavation"],
    "ja": ["第3図: 土器出土状況"]
  },

  // Optional human-readable summary
  "summary": {
    "en": ["Catalog figure from site report"],
    "ja": ["発掘調査報告書の資料図版"]
  },

  "items": [
    {
      "id": "https://example.com/iiif/manifest/img-42-12345/canvas/1",
      "type": "Canvas",
      "width": 800,
      "height": 600,
      "items": [
        {
          "id": "https://example.com/iiif/manifest/img-42-12345/canvas/1/page",
          "type": "AnnotationPage",
          "items": [
            {
              "id": "https://example.com/iiif/manifest/img-42-12345/canvas/1/page/annotation",
              "type": "Annotation",
              "motivation": "painting",
              "body": {
                // Image API v3.0 service reference
                "id": "https://example.com/iiif/image/img-42-12345/full/max/0/default.jpg",
                "type": "Image",
                "format": "image/jpeg",
                "width": 800,
                "height": 600,
                "service": [
                  {
                    "@context": "http://iiif.io/api/image/3/context.json",
                    "id": "https://example.com/iiif/image/img-42-12345",
                    "type": "ImageService3",
                    "profile": "level2"
                  }
                ]
              },
              "target": "https://example.com/iiif/manifest/img-42-12345/canvas/1"
            }
          ]
        }
      ]
    }
  ]
}
```

### 3.2 Source-Level Manifest (Collection)

A PdfSource-level Manifest aggregates multiple published images as Canvases.
Canvas dimensions are derived from `geometry.width` / `geometry.height`
(fallback: 1000×1000 if geometry is unavailable).

PdfSource 単位の Manifest は、複数の公開済み画像を Canvas として集約します。
Canvas のサイズは `geometry.width` / `geometry.height` から取得します（フォールバック: 1000×1000）。

```json
{
  "@context": "http://iiif.io/api/presentation/3/context.json",

  "id": "https://example.com/iiif/presentation/7/manifest",
  "type": "Manifest",

  "label": {
    "en": ["Site Report: Nagaoka Excavation 2023"],
    "ja": ["長岡市発掘調査報告書 2023"]
  },

  // Canvases are ordered by page_number ascending
  "items": [
    {
      "id": "https://example.com/iiif/presentation/7/manifest/canvas/1",
      "type": "Canvas",
      "width": 800,
      "height": 600,
      "label": { "en": ["Figure 1"], "ja": ["第1図"] },
      "items": [ /* AnnotationPage → Annotation → Image body */ ]
    },
    {
      "id": "https://example.com/iiif/presentation/7/manifest/canvas/2",
      "type": "Canvas",
      "width": 800,
      "height": 600,
      "label": { "en": ["Figure 2"], "ja": ["第2図"] },
      "items": [ /* ... */ ]
    }
  ]
}
```

---

## 4. Viewer Compatibility / ビューア互換性

OmniArchive Manifests are designed to load in standard IIIF viewers.
The table below shows compatibility status.

OmniArchive の Manifest は標準 IIIF ビューアでの読み込みを想定しています。

| Viewer | Version | Status | Notes |
|:---|:---|:---|:---|
| [Mirador](https://projectmirador.org/) | 3.x | Not yet verified / 未検証 | Presentation API v3.0 support available in Mirador 3 |
| [Universal Viewer](https://universalviewer.io/) | 4.x | Not yet verified / 未検証 | UV 4 supports IIIF Presentation API v3.0 |
| [Clover IIIF](https://samvera-labs.github.io/clover-iiif/) | latest | Not yet verified / 未検証 | React-based viewer; v3.0 Manifest support |

> Viewer testing is planned. Confirmed results will replace the "Not yet verified" status
> in a future update.

---

## 5. Image Processing / 画像処理

### PTIF Generation / PTIF 生成

OmniArchive generates Pyramidal TIFF (PTIF) files from cropped images using the
[vix](https://github.com/akash-akya/vix) library (a libvips wrapper for Elixir).

- **Compression**: DEFLATE lossless compression prevents mosquito noise on line drawings.
- **Lazy generation**: PTIF files are generated only when an administrator approves an
  image. This avoids unnecessary CPU and storage use during editing.
- **Tile serving**: The Image API controller reads PTIF tiles via vix and caches them
  in `priv/static/iiif_cache`.

PTIF ファイルは管理者の承認時に初めて生成されます（Lazy Generation）。
DEFLATE 可逆圧縮により線画のモスキートノイズを防止します。

### Polygon Crop Processing / ポリゴンクロップ処理

When a crop has a `points` array (polygon geometry), OmniArchive uses a 4-step
pipeline in `ImageProcessor`:

1. Extract bounding box with `extract_area`
2. Generate an SVG mask from the polygon points
3. Composite with white background using `ifthenelse`
4. Output as a 3-band RGB JPEG (no alpha channel required)

Polygon areas outside the crop region are filled with pure white (255, 255, 255),
producing JPEG-compatible output.

---

## 6. Technical Stack / 技術スタック

| Component | Technology |
|:---|:---|
| Language / Framework | Elixir 1.15+ / Phoenix 1.8+ (LiveView) |
| Database | PostgreSQL 15+ — JSONB for metadata and geometry |
| Image processing | [vix](https://github.com/akash-akya/vix) (libvips wrapper) |
| PDF conversion | [poppler-utils](https://poppler.freedesktop.org/) (`pdftoppm`) |
| Tile cache | `priv/static/iiif_cache` (filesystem) |
| Frontend crop UI | Phoenix LiveView + custom JS Hook (`ImageSelection`) |

---

## 7. Data Schema / データスキーマ

### Core Tables / 主要テーブル

| Table | Role | Key Fields |
|:---|:---|:---|
| `pdf_sources` | PDF tracking | `filename`, `page_count`, `status`, `workflow_status` |
| `extracted_images` | Figure assets | `image_path`, `geometry` (JSONB), `status`, `metadata` (JSONB), `owner_id`, `worker_id` |
| `iiif_manifests` | Manifest entities | `identifier`, `metadata` (JSONB) |
| `users` | Authentication | `email`, `hashed_password`, `confirmed_at` |

### Geometry JSONB Format / geometry JSONB 形式

**Rectangle (legacy / 後方互換):**
```json
{ "x": 150, "y": 200, "width": 800, "height": 600 }
```

**Polygon (v0.2.22+):**
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

### Manifest Metadata JSONB Format / Manifest metadata JSONB 形式

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

---

## 8. Stage-Gate Workflow / Stage-Gate ワークフロー

| Stage | Status | Description |
|:---|:---|:---|
| Lab (internal) | `draft` | Upload, crop, and label within the internal workspace |
| Submitted | `pending_review` | Submitted for administrator approval |
| Rejected | `rejected` | Returned for correction; `review_comment` stores the reason |
| Published | `published` | Approved and visible in Gallery; IIIF endpoints become active |

Only images with `published` status are served by the IIIF endpoints.

`published` ステータスの画像のみが IIIF エンドポイントから配信されます。

---

## 9. Ingestion Workflow / 取り込みワークフロー

The ingestion pipeline follows a strict 5-step wizard pattern designed for cognitive
accessibility. All selection and metadata entry is performed manually by the user;
no automated extraction is used.

取り込みパイプラインは5ステップのウィザード形式で、認知アクセシビリティを最優先にしています。
図版の選択とメタデータ入力はすべてユーザーが手動で行います。

1. **Upload** — Submit PDF. Pages are converted to 300 DPI PNG in 10-page chunks.
2. **Browse** — Select pages containing figures from a thumbnail grid. No DB record is created at this stage (Write-on-Action policy).
3. **Crop** — Draw a polygon over the figure using the `ImageSelection` JS Hook. D-Pad Nudge buttons (min 60×60px) allow fine adjustment. Saving the crop creates the `ExtractedImage` record.
4. **Label** — Enter caption, label, and profile-defined metadata. Auto-saved in real time.
5. **Submit** — Final review and submission for administrator approval.

---

## 10. Developer Reference / 開発者向け参考情報

For implementation details beyond this specification, see:

| Document | Description |
|:---|:---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Module structure, OTP supervision tree, data flow diagrams |
| [PROFILES.md](PROFILES.md) | YAML-based domain profile configuration |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to add domain profiles and contribute to the project |
| [DEPLOYMENT.md](DEPLOYMENT.md) | Docker and OTP release deployment instructions |

### Caching

Tile responses are cached in `priv/static/iiif_cache/{identifier}/` after the first
request. The cache is not automatically invalidated on PTIF update; clear the directory
manually if a PTIF is regenerated.

タイルレスポンスは初回リクエスト後に `priv/static/iiif_cache/{identifier}/` にキャッシュされます。
PTIF を再生成した場合は手動でディレクトリを削除してください。

### Search Index

Full-text search (FTS) on captions uses PostgreSQL `tsvector` with a `GIN` index.
Faceted filtering is driven by the active domain profile's metadata field definitions.

キャプションの全文検索は PostgreSQL `tsvector` + `GIN` インデックスを使用します。
ファセット検索はアクティブなドメインプロファイルのメタデータフィールド定義に基づきます。
