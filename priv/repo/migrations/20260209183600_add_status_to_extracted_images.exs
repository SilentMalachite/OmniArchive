defmodule AlchemIiif.Repo.Migrations.AddStatusToExtractedImages do
  use Ecto.Migration

  def change do
    alter table(:extracted_images) do
      # ステータスカラム: draft / pending_review / published
      add :status, :string, default: "draft", null: false
    end

    # ステータスでの検索を高速化するインデックス
    create index(:extracted_images, [:status])
  end
end
