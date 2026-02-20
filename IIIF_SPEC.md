# OmniArchive Development Specification (IIIF_SPEC.md)

## 1. Project Overview

OmniArchive is a modular-monolith application built with Elixir and Phoenix. It is designed to transform static PDF archaeological reports into rich, interoperable IIIF (International Image Interoperability Framework) assets.

### Core Philosophy
- **Modular Monolith:** Decouples the "Manual Ingestion & Inspection" module from the "IIIF Delivery" module within a single codebase to ensure maintainability and clear boundaries.
- **Cognitive Accessibility (Primary UX Goal):** Specifically designed for users in vocational support settings. The UI prioritizes simplicity, low working memory load, and motor-skill-friendly interactions (e.g., utilize large, high-contrast buttons instead of precision-heavy drag-and-drop operations).

## 2. Technical Stack

- **Language/Framework:** Elixir 1.15+ / Phoenix 1.7+ (LiveView).
- **Database:** PostgreSQL 15+ (utilizing JSONB for flexible metadata and geometry storage).
- **Image Processing:** [vix](https://github.com/akash-akya/vix) (libvips wrapper) for real-time tiling and Pyramidal TIFF (PTIF) generation.
- **PDF Processing:** [poppler-utils](https://poppler.freedesktop.org/) (specifically `pdftoppm`) for high-fidelity conversion of PDF pages to images.
- **Frontend:** Phoenix LiveView with Custom JS Hooks (`ImageSelection`) for precise coordinate mapping.

## 3. Data Schema (PostgreSQL Strategy)

Ecto schemas will focus on the following core entities:

| Table Name | Role | Key Fields | Ecto Data Type |
| :--- | :--- | :--- | :--- |
| `pdf_sources` | PDF Tracking | `filename`, `page_count`, `status` | `:string`, `:integer`, `:string` |
| `extracted_images` | Figure Assets | `image_path`, `geometry`, `status`, `site`, `period`, `artifact_type`, `owner_id`, `worker_id` | `:string`, `:map`, `:string`... |
| `iiif_manifests` | Manifest Entities | `identifier`, `metadata` | `:string`, `:map` (JSONB) |
| `users` | Authentication | `email`, `hashed_password`, `confirmed_at` | `:string`, `:string`, `:utc_datetime` |

### 3.1 Strict Validation Rules

To ensure data integrity, the system enforces the following validations:

- **Label Format:** Must match `fig-{number}-{number}` (e.g., `fig-1-1`).
- **Municipality Check:** The `site` field must contain "市" (City), "町" (Town), or "村" (Village).
- **Uniqueness:** A composite unique index on `[:site, :label]` prevents duplicate labels within the same site.
- **File Versioning:** Uploaded files are renamed to `filename-{timestamp}.ext` to prevent browser caching issues and collisions.
- **Ownership:** `owner_id` (uploader) and `worker_id` (current editor) foreign keys to `users` table.

## 3.2 Authentication & Authorization

- **Session-based Authentication:** `phx.gen.auth` with `bcrypt_elixir`.
- **Protected Routes:** `/lab/*` and `/admin/*` require authenticated users (`require_authenticated_user` plug).
- **Public Routes:** `/`, `/gallery`, `/iiif/*`, `/api/health` are accessible without authentication.
- **Default Admin:** `seeds.exs` creates `admin@example.com` / `password1234` for development.

## 4. Stage-Gate Workflow (Laboratory vs Gallery)

To ensure quality control and separate internal workflows from public access, the system implements a strict Stage-Gate model.

### 4.1 Concept
- **Laboratory (Internal):** A private workspace for archaeologists/researchers to upload, crop, and annotate images. Content here is in `draft` or `pending_review` status.
- **Gallery (Public):** The public-facing gallery and IIIF endpoints. Only content with `published` status is accessible here.

### 4.2 Status Lifecycle
1. **Draft:** Initial creation logic (Ingestion).
2. **Pending Review:** Submitted for approval.
3. **Rejected:** Returned for corrections. The `review_comment` field stores the rejection reason. Can be resubmitted via `resubmit_image/1`.
4. **Published:** Approved and visible in the Gallery.

## 5. Search & Discovery

### 5.1 Metadata Schema
To support academic research, specific archaeological metadata fields are indexed:
- **Site Name (遺跡名)**
- **Period (時代)**
- **Artifact Type (遺物種別)**
- **Caption (キャプション - Full Text Search)**

### 5.2 Implementation Strategy
- **PostgreSQL FTS:** Utilizes `tsvector` and `GIN` indexes for performant full-text search on captions.
- **Faceted Search:** LiveView-driven filtering by Period and Artifact Type.

## 6. IIIF Server Implementation (Delivery)

### 4.1 Image API (v3.0)
- **Endpoint:** `/iiif/image/:identifier/:region/:size/:rotation/:quality.:format`
- **Logic:** Read PTIF files via `vix` and dynamically generate tiles according to the IIIF Image API specification.
- **Caching:** Store processed tiles in `priv/static/iiif_cache` to optimize performance.

### 4.2 Presentation API (v3.0)

**Individual Image Manifest:**
- **Endpoint:** `GET /iiif/manifest/:identifier`
- **Output:** JSON-LD format strictly matching IIIF 3.0 specifications.
- **Localization:** Support multilingual labels (English/Japanese) as specified in the IIIF metadata requirements.

**PdfSource-level Manifest (Collection):**
- **Endpoint:** `GET /iiif/presentation/:source_id/manifest`
- **Output:** JSON-LD Manifest aggregating all `published` images under a PdfSource as Canvases.
- **Canvas ordering:** Sorted by `page_number` ascending.
- **Canvas dimensions:** Derived from `geometry.width` / `geometry.height` (fallback: 1000×1000).
- **Image URL:** Absolute URL constructed from `image_path` via `OmniArchiveWeb.Endpoint.url()`.

## 7. "Manual Inspector" Workflow (Ingestion Pipeline)

To ensure a stress-free user experience, the ingestion process is strictly divided into human-driven, sequential steps (Wizard pattern).

### 7.1 Wizard-Style Flow (5 Steps)
1. **Upload (📄 アップロード):** Submit the PDF. The system automatically converts all pages into high-resolution PNGs for inspection.
2. **Browse & Select (🔍 ページ選択):** User browses a grid of page thumbnails and manually selects a page containing a figure/illustration.
3. **Manual Crop (✂️ クロップ):** User defines figure boundaries using a custom JS Hook (`ImageSelection`) with D-Pad Nudge controls. **Double-click** (or double-tap) inside the selection to save.
4. **Labeling (🏷️ ラベリング):** Captions, labels, and archaeological metadata are entered manually. Labels are validated for uniqueness within the PDF. PTIF generation starts automatically in the background upon completion.
5. **Review & Submit (✅ レビュー提出):** User verifies the final metadata and submits for admin review.

### 7.2 Accessibility Feature: "Nudge" Controls
The UI provides large (min 60x60px) directional buttons (Up, Down, Left, Right) to allow users to incrementally adjust the crop area. This reduces the cognitive and motor load associated with precise pointer movements.

## 8. Key Implementation Snippets

### 8.1 JS Hook (Manual Crop with Nudge & Double-Click support)

```javascript
// assets/js/hooks/image_selection_hook.js
const ImageSelection = {
  mounted() {
    // Custom logic for coordinate mapping between CSS and original image size.
    // Supports dragging to select, Nudge button events from LiveView,
    // and keyboard arrow keys.
    this.handleEvent("nudge_crop", ({ direction, amount }) => {
      // Logic to nudge selection coordinates...
    });

    // Double-click to save
    this.el.addEventListener('dblclick', (e) => {
      if (this.isInSelection(e)) {
        this.pushEvent("save_crop", this.currentRect);
      }
    });
  }
};
```

## 9. UX & Accessibility Requirements

- **Simplicity:** Clean UI with zero hidden menus. Use large, high-contrast, easily clickable elements.
- **Linearity:** Use a "Wizard" pattern to prevent users from becoming lost in complex or non-linear navigation.
- **Masonry Layout:** The Gallery uses a masonry grid layout (CSS Multi-column) to display images of varying aspect ratios without cropping, preserving their original composition.
- **Write-on-Action:** Database records are only created when the user explicitly saves a crop (Step 3), preventing "ghost records" from cluttering the database during browsing.
- **Immediate Feedback:** Provide clear visual confirmation (e.g., "Image Saved Successfully!") and require explicit confirmation for destructive actions.
- **Human-in-the-loop:** Optimize manual data entry (captions/metadata) through structured, accessible forms rather than automated extraction.

## 10. Implementation Instructions for AI Agents (Antigravity)

**System Prompt / Directive:**
> Implement the OmniArchive modular monolith following this IIIF_SPEC.md exactly. 
> 1. **Manual Ingestion Pipeline:** Build the 'Inspector' using Phoenix LiveView with a strict Wizard-style flow.
> 2. **Accessibility Controls:** Implement the `nudge_crop` functionality using large, accessible UI buttons as specified. 
> 3. **Persistence:** Use PostgreSQL with JSONB to store flexible metadata and crop geometry.
> 4. **IIIF Delivery:** Implement the IIIF Image API v3.0 using the `vix` library to serve tiles from generated PTIF files.
> 5. **UX Priority:** The system must not rely on AI for figure extraction; all selection and metadata entry must be user-driven through the high-accessibility interface.