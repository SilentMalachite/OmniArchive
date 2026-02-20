defmodule AlchemIiif.Repo.Migrations.AddReviewCommentAndRejectedStatus do
  use Ecto.Migration

  def change do
    alter table(:extracted_images) do
      # レビュアーによる差し戻し理由を保存する専用カラム
      add :review_comment, :text
    end
  end
end
