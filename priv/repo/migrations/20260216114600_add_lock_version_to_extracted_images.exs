defmodule AlchemIiif.Repo.Migrations.AddLockVersionToExtractedImages do
  use Ecto.Migration

  def change do
    alter table(:extracted_images) do
      add :lock_version, :integer, default: 1, null: false
    end
  end
end
