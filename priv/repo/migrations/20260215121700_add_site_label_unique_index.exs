defmodule OmniArchive.Repo.Migrations.AddSiteLabelUniqueIndex do
  @moduledoc """
  ユニークインデックスを [:pdf_source_id, :label] から [:site, :label] に変更。
  同一遺跡内で同じラベルを持つレコードを DB レベルで禁止します。

  条件:
  - site と label が NULL でも空文字でもない場合のみ制約を適用
  - status が 'deleted' のレコードは除外（論理削除に対応）
  """
  use Ecto.Migration

  def change do
    # 旧インデックスを削除
    drop_if_exists unique_index(:extracted_images, [:pdf_source_id, :label],
                     name: :extracted_images_pdf_source_id_label_unique
                   )

    # 新しい部分ユニークインデックス: (site, label)
    create unique_index(:extracted_images, [:site, :label],
             where:
               "site IS NOT NULL AND site != '' AND label IS NOT NULL AND label != '' AND status != 'deleted'",
             name: :extracted_images_site_label_unique
           )
  end
end
