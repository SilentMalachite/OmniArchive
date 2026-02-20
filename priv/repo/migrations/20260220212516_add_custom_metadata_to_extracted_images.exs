defmodule OmniArchive.Repo.Migrations.AddCustomMetadataToExtractedImages do
  use Ecto.Migration

  def change do
    alter table(:extracted_images) do
      add :custom_metadata, :map, default: %{}
    end
  end
end
