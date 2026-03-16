defmodule OmniArchive.Repo.Migrations.AddOwnershipToExtractedImages do
  use Ecto.Migration

  def change do
    alter table(:extracted_images) do
      # アップロードした人（元の所有者）
      add :owner_id, references(:users, on_delete: :nilify_all)
      # 現在編集中/作業中の人
      add :worker_id, references(:users, on_delete: :nilify_all)
    end

    create index(:extracted_images, [:owner_id])
    create index(:extracted_images, [:worker_id])
  end
end
