defmodule OmniArchive.Repo.Migrations.AddUserIdToPdfSources do
  use Ecto.Migration

  def change do
    alter table(:pdf_sources) do
      # ユーザー所有権カラム（既存データとの互換性のため null: true）
      add :user_id, references(:users, on_delete: :nothing), null: true
    end

    create index(:pdf_sources, [:user_id])
  end
end
