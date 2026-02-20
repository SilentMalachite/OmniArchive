defmodule AlchemIiif.Repo.Migrations.AddPg15JsonbOptimizations do
  @moduledoc """
  PostgreSQL 15+ JSONB 最適化マイグレーション。

  PG15 以降の改善された GIN インデックス性能を活用し、
  JSONB カラムに jsonb_path_ops GIN インデックスを追加します。

  非破壊性保証:
  - 既存カラムの変更・削除は一切行いません
  - インデックスのみ追加（Additive）
  - CONCURRENTLY で安全に作成
  """
  use Ecto.Migration

  # CONCURRENTLY インデックス作成のためトランザクション・ロックを無効化
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # IIIF メタデータの JSONB containment クエリを高速化
    execute(
      "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_iiif_manifests_metadata_gin ON iiif_manifests USING gin(metadata jsonb_path_ops)",
      "DROP INDEX IF EXISTS idx_iiif_manifests_metadata_gin"
    )

    # クロップデータの JSONB クエリを高速化（将来的な拡張に備える）
    execute(
      "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_extracted_images_geometry_gin ON extracted_images USING gin(geometry jsonb_path_ops)",
      "DROP INDEX IF EXISTS idx_extracted_images_geometry_gin"
    )
  end
end
