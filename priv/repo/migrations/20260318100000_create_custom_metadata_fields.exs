defmodule OmniArchive.Repo.Migrations.CreateCustomMetadataFields do
  use Ecto.Migration

  def change do
    create table(:custom_metadata_fields) do
      add :field_key, :string, null: false
      add :label, :string, null: false
      add :placeholder, :string, default: ""
      add :sort_order, :integer, default: 0
      add :searchable, :boolean, default: false
      add :validation_rules, :map, default: %{}
      add :active, :boolean, default: true
      add :profile_key, :string, null: false

      timestamps()
    end

    create unique_index(:custom_metadata_fields, [:profile_key, :field_key])
    create index(:custom_metadata_fields, [:profile_key, :active])
  end
end
