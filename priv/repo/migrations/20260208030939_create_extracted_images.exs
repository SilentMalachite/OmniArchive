defmodule AlchemIiif.Repo.Migrations.CreateExtractedImages do
  use Ecto.Migration

  def change do
    create table(:extracted_images) do
      # PDF ソースへの外部キー
      add :pdf_source_id, references(:pdf_sources, on_delete: :delete_all), null: false
      # 抽出元のページ番号
      add :page_number, :integer, null: false
      # 抽出画像のファイルパス
      add :image_path, :string
      # クロップデータ (x, y, width, height) — JSONB
      add :geometry, :map
      # キャプション (手動入力)
      add :caption, :string
      # ラベル (手動入力)
      add :label, :string
      # 生成された PTIF のパス
      add :ptif_path, :string

      timestamps(type: :utc_datetime)
    end

    create index(:extracted_images, [:pdf_source_id])
  end
end
