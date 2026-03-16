defmodule OmniArchive.Repo.Migrations.CreatePdfSources do
  use Ecto.Migration

  def change do
    create table(:pdf_sources) do
      # PDFファイル名
      add :filename, :string, null: false
      # ページ数
      add :page_count, :integer
      # 処理ステータス (uploading, converting, ready, error)
      add :status, :string, null: false, default: "uploading"

      timestamps(type: :utc_datetime)
    end
  end
end
