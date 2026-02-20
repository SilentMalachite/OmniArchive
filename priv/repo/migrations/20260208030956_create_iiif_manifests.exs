defmodule OmniArchive.Repo.Migrations.CreateIiifManifests do
  use Ecto.Migration

  def change do
    create table(:iiif_manifests) do
      # 抽出画像への外部キー
      add :extracted_image_id, references(:extracted_images, on_delete: :delete_all), null: false
      # IIIF 識別子
      add :identifier, :string, null: false
      # IIIF メタデータ (多言語ラベル等) — JSONB
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:iiif_manifests, [:identifier])
    create index(:iiif_manifests, [:extracted_image_id])
  end
end
