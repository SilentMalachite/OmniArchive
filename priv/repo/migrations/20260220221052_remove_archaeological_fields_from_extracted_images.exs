defmodule OmniArchive.Repo.Migrations.RemoveArchaeologicalFieldsFromExtractedImages do
  use Ecto.Migration

  def up do
    drop_if_exists index(:extracted_images, [:site, :label],
                     name: :extracted_images_site_label_unique
                   )

    alter table(:extracted_images) do
      remove :site, :string
      remove :period, :string
      remove :artifact_type, :string
    end
  end

  def down do
    alter table(:extracted_images) do
      add :site, :string
      add :period, :string
      add :artifact_type, :string
    end

    create unique_index(:extracted_images, [:site, :label],
             name: :extracted_images_site_label_unique
           )
  end
end
