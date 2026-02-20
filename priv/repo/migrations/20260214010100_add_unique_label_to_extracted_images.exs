defmodule OmniArchive.Repo.Migrations.AddUniqueLabelToExtractedImages do
  @moduledoc """
  ラベル重複防止のための部分ユニークインデックスを追加。
  同一 PDF 内で同じラベルを持つレコードを DB レベルで禁止します。

  条件:
  - label が NULL でも空文字でもない場合のみ制約を適用
  - status が 'deleted' のレコードは除外（将来の論理削除に対応）
  """
  use Ecto.Migration

  def change do
    # 部分ユニークインデックス: (pdf_source_id, label)
    # ラベル未入力の draft レコード同士は重複を許可
    create unique_index(:extracted_images, [:pdf_source_id, :label],
             where: "label IS NOT NULL AND label != '' AND status != 'deleted'",
             name: :extracted_images_pdf_source_id_label_unique
           )
  end
end
