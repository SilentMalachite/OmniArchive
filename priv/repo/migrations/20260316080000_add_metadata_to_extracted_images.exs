defmodule OmniArchive.Repo.Migrations.AddMetadataToExtractedImages do
  @moduledoc """
  extracted_images に可変メタデータ用 JSONB カラムを追加し、
  既存の archaeology 専用カラム値を backfill します。
  """

  use Ecto.Migration

  def up do
    alter table(:extracted_images) do
      add_if_not_exists :metadata, :map, default: %{}, null: false
    end

    execute("""
    UPDATE extracted_images
    SET metadata = jsonb_strip_nulls(
      COALESCE(metadata, '{}'::jsonb) ||
      jsonb_build_object(
        'site', CASE WHEN COALESCE(metadata, '{}'::jsonb) ? 'site' THEN NULL ELSE NULLIF(site, '') END,
        'period', CASE WHEN COALESCE(metadata, '{}'::jsonb) ? 'period' THEN NULL ELSE NULLIF(period, '') END,
        'artifact_type', CASE WHEN COALESCE(metadata, '{}'::jsonb) ? 'artifact_type' THEN NULL ELSE NULLIF(artifact_type, '') END
      )
    )
    WHERE
      (NOT (COALESCE(metadata, '{}'::jsonb) ? 'site') AND site IS NOT NULL AND site != '') OR
      (NOT (COALESCE(metadata, '{}'::jsonb) ? 'period') AND period IS NOT NULL AND period != '') OR
      (NOT (COALESCE(metadata, '{}'::jsonb) ? 'artifact_type') AND artifact_type IS NOT NULL AND artifact_type != '')
    """)
  end

  def down do
    alter table(:extracted_images) do
      remove :metadata
    end
  end
end
