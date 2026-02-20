defmodule OmniArchive.Repo.Migrations.AddDeletedAtToPdfSources do
  use Ecto.Migration

  def change do
    alter table(:pdf_sources) do
      # ソフトデリート用タイムスタンプ（nil = アクティブ、値あり = ゴミ箱内）
      add :deleted_at, :utc_datetime, default: nil
    end

    # ゴミ箱一覧クエリの高速化用インデックス
    create index(:pdf_sources, [:deleted_at])
  end
end
