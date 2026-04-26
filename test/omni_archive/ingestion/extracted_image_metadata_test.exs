defmodule OmniArchive.Ingestion.ExtractedImageMetadataTest do
  use OmniArchive.DataCase, async: false

  alias OmniArchive.DuplicateIdentity
  alias OmniArchive.Ingestion.ExtractedImage
  alias OmniArchive.Ingestion.ExtractedImageMetadata
  alias OmniArchive.Repo
  import OmniArchive.Factory
  import OmniArchive.DomainProfileTestHelper

  setup do
    put_domain_profile(OmniArchive.DomainProfiles.Archaeology)
    :ok
  end

  describe "migration / backfill" do
    test "metadata column exists on extracted_images" do
      %{rows: rows} =
        Repo.query!("""
        SELECT column_name
        FROM information_schema.columns
        WHERE table_name = 'extracted_images' AND column_name = 'metadata'
        """)

      assert rows == [["metadata"]]
    end

    test "backfill copies legacy archaeology fields into metadata" do
      image =
        insert_extracted_image(%{
          site: "新潟市中野遺跡",
          period: "縄文時代",
          artifact_type: "土器"
        })

      Repo.query!("UPDATE extracted_images SET metadata = '{}'::jsonb WHERE id = $1", [image.id])

      assert ExtractedImageMetadata.backfill_from_legacy_fields() >= 1

      reloaded = Repo.get!(ExtractedImage, image.id)

      assert reloaded.metadata == %{
               "site" => "新潟市中野遺跡",
               "period" => "縄文時代",
               "artifact_type" => "土器"
             }
    end

    test "fingerprint backfill populates missing dedupe_fingerprint" do
      image =
        insert_extracted_image(%{
          site: "新潟市中野遺跡",
          label: "fig-1-1"
        })

      Repo.query!("UPDATE extracted_images SET dedupe_fingerprint = NULL WHERE id = $1", [
        image.id
      ])

      assert DuplicateIdentity.backfill_missing_fingerprints() >= 1

      reloaded = Repo.get!(ExtractedImage, image.id)
      assert reloaded.dedupe_fingerprint == "v1|archaeology|新潟市中野遺跡|fig-1-1"
    end
  end
end
