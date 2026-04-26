defmodule OmniArchive.DuplicateLookupTest do
  use OmniArchive.DataCase, async: false

  alias OmniArchive.Ingestion
  import OmniArchive.DomainProfileTestHelper
  import OmniArchive.Factory

  describe "find_duplicate_extracted_image/2" do
    test "Archaeology で duplicate fingerprint を使って重複を見つける" do
      put_domain_profile(OmniArchive.DomainProfiles.Archaeology)
      existing =
        insert_extracted_image(%{
          site: "新潟市中野遺跡",
          label: "fig-1-1"
        })

      duplicate =
        Ingestion.find_duplicate_extracted_image(%OmniArchive.Ingestion.ExtractedImage{}, %{
          site: "新潟市中野遺跡",
          label: "fig-1-1"
        })

      assert duplicate.id == existing.id
    end

    test "scope または label が空なら lookup しない" do
      assert is_nil(
               Ingestion.find_duplicate_extracted_image(
                 %OmniArchive.Ingestion.ExtractedImage{},
                 %{
                   site: "新潟市中野遺跡",
                   label: ""
                 }
               )
             )

      assert is_nil(
               Ingestion.find_duplicate_extracted_image(
                 %OmniArchive.Ingestion.ExtractedImage{},
                 %{
                   site: "",
                   label: "fig-1-1"
                 }
               )
             )
    end

    test "deleted status のレコードは重複候補から除外する" do
      insert_extracted_image(%{
        site: "新潟市中野遺跡",
        label: "fig-1-1",
        status: "deleted"
      })

      assert is_nil(
               Ingestion.find_duplicate_extracted_image(
                 %OmniArchive.Ingestion.ExtractedImage{},
                 %{
                   site: "新潟市中野遺跡",
                   label: "fig-1-1"
                 }
               )
             )
    end

    test "GeneralArchive の metadata-only scope でも lookup できる" do
      put_domain_profile(OmniArchive.DomainProfiles.GeneralArchive)

      existing =
        insert_extracted_image(%{
          label: "photo-001",
          metadata: %{"collection" => "広報写真アーカイブ"}
        })

      duplicate =
        Ingestion.find_duplicate_extracted_image(%OmniArchive.Ingestion.ExtractedImage{}, %{
          label: "photo-001",
          metadata: %{"collection" => "広報写真アーカイブ"}
        })

      assert duplicate.id == existing.id
    end
  end
end
