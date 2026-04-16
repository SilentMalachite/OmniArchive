defmodule OmniArchive.Repo.Migrations.RenameCaptionToSummary do
  use Ecto.Migration

  def change do
    rename table(:extracted_images), :caption, to: :summary

    # Drop old FTS index
    execute(
      "DROP INDEX IF EXISTS idx_extracted_images_caption_fts",
      "CREATE INDEX IF NOT EXISTS idx_extracted_images_caption_fts ON extracted_images USING gin(to_tsvector('simple', coalesce(caption, '')))"
    )

    # Create new FTS index
    execute(
      "CREATE INDEX IF NOT EXISTS idx_extracted_images_summary_fts ON extracted_images USING gin(to_tsvector('simple', coalesce(summary, '')))",
      "DROP INDEX IF EXISTS idx_extracted_images_summary_fts"
    )
  end
end
