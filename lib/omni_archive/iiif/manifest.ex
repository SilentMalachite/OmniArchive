defmodule OmniArchive.IIIF.Manifest do
  @moduledoc """
  IIIF Manifest を管理する Ecto スキーマ。
  メタデータ(多言語ラベル等)をJSONBで保持します。

  ## なぜこの設計か

  - **IIIF Presentation API 3.0 準拠**: 国際的なデジタルアーカイブ規格に
    従うことで、Mirador や Universal Viewer などの既存ビューアと
    互換性を持たせています。独自フォーマットではなく標準に従うことで、
    他のデジタルアーカイブとの相互運用性を確保します。
  - **metadata を JSONB で保持**: IIIF のメタデータ構造は多言語対応の
    入れ子構造（`{\"en\": [...], \"ja\": [...]}`）を持つため、
    JSONB カラムが最も自然にフィットします。
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "iiif_manifests" do
    # IIIF 識別子
    field :identifier, :string
    # IIIF メタデータ (多言語ラベル等) — JSONB
    field :metadata, :map, default: %{}

    belongs_to :extracted_image, OmniArchive.Ingestion.ExtractedImage

    timestamps(type: :utc_datetime)
  end

  @doc "バリデーション用 changeset"
  def changeset(manifest, attrs) do
    manifest
    |> cast(attrs, [:extracted_image_id, :identifier, :metadata])
    |> validate_required([:extracted_image_id, :identifier])
    |> unique_constraint(:identifier)
    |> foreign_key_constraint(:extracted_image_id)
  end
end
