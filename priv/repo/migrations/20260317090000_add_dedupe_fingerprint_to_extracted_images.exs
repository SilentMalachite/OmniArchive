defmodule OmniArchive.Repo.Migrations.AddDedupeFingerprintToExtractedImages do
  @moduledoc """
  profile 駆動の重複判定用 fingerprint を extracted_images に追加します。

  移行方針:
  - dedupe_fingerprint カラムを additive に追加
  - 既知 profile の fingerprint を SQL で backfill
  - fingerprint ベースの部分ユニークインデックスを追加
  - 旧 site + label 制約は新制約作成後に削除
  """

  use Ecto.Migration

  def up do
    alter table(:extracted_images) do
      add_if_not_exists :dedupe_fingerprint, :string
    end

    # metadata-only profile を優先して backfill
    execute("""
    UPDATE extracted_images
    SET dedupe_fingerprint = CONCAT(
      'v1|general_archive|',
      LOWER(BTRIM(metadata->>'collection')),
      '|',
      LOWER(BTRIM(label))
    )
    WHERE
      (dedupe_fingerprint IS NULL OR dedupe_fingerprint = '')
      AND label IS NOT NULL AND BTRIM(label) != ''
      AND metadata ? 'collection'
      AND BTRIM(COALESCE(metadata->>'collection', '')) != ''
    """)

    execute("""
    UPDATE extracted_images
    SET dedupe_fingerprint = CONCAT(
      'v1|archaeology|',
      LOWER(BTRIM(COALESCE(metadata->>'site', site))),
      '|',
      LOWER(BTRIM(label))
    )
    WHERE
      (dedupe_fingerprint IS NULL OR dedupe_fingerprint = '')
      AND label IS NOT NULL AND BTRIM(label) != ''
      AND BTRIM(COALESCE(metadata->>'site', site, '')) != ''
    """)

    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT dedupe_fingerprint
        FROM extracted_images
        WHERE
          status != 'deleted'
          AND dedupe_fingerprint IS NOT NULL
          AND dedupe_fingerprint != ''
        GROUP BY dedupe_fingerprint
        HAVING COUNT(*) > 1
      ) THEN
        RAISE EXCEPTION 'duplicate dedupe_fingerprint values exist; resolve duplicates before applying unique index';
      END IF;
    END
    $$;
    """)

    create unique_index(:extracted_images, [:dedupe_fingerprint],
             where:
               "dedupe_fingerprint IS NOT NULL AND dedupe_fingerprint != '' AND status != 'deleted'",
             name: :extracted_images_dedupe_fingerprint_unique
           )

    drop_if_exists unique_index(:extracted_images, [:site, :label],
                     name: :extracted_images_site_label_unique
                   )
  end

  def down do
    drop_if_exists unique_index(:extracted_images, [:dedupe_fingerprint],
                     name: :extracted_images_dedupe_fingerprint_unique
                   )

    create_if_not_exists unique_index(:extracted_images, [:site, :label],
                           where:
                             "site IS NOT NULL AND site != '' AND label IS NOT NULL AND label != '' AND status != 'deleted'",
                           name: :extracted_images_site_label_unique
                         )

    alter table(:extracted_images) do
      remove :dedupe_fingerprint
    end
  end
end
