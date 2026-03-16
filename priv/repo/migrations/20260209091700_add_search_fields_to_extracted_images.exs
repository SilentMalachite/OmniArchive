defmodule OmniArchive.Repo.Migrations.AddSearchFieldsToExtractedImages do
  @moduledoc """
  検索エンジン用のカラムを extracted_images テーブルに追加するマイグレーション。

  非破壊性保証:
  - 既存カラムの変更・削除は一切行いません
  - 新規カラムの追加のみ（Additive）
  - インデックスは CONCURRENTLY で作成
  """
  use Ecto.Migration

  # CONCURRENTLY インデックス作成のためトランザクション・ロックを無効化
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # 検索用メタデータカラムの追加（既存カラムへの変更なし）
    alter table(:extracted_images) do
      # 遺跡名
      add_if_not_exists :site, :string
      # 時代
      add_if_not_exists :period, :string
      # 遺物種別
      add_if_not_exists :artifact_type, :string
    end

    # FTS 用 GIN インデックス（CONCURRENTLY で安全に作成）
    execute(
      "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_extracted_images_caption_fts ON extracted_images USING gin(to_tsvector('simple', coalesce(caption, '')))",
      "DROP INDEX IF EXISTS idx_extracted_images_caption_fts"
    )

    # フィルター用インデックス
    create_if_not_exists index(:extracted_images, [:site], concurrently: true)
    create_if_not_exists index(:extracted_images, [:period], concurrently: true)
    create_if_not_exists index(:extracted_images, [:artifact_type], concurrently: true)
  end
end
