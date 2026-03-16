defmodule OmniArchive.DuplicateIdentityTest do
  use OmniArchive.DataCase, async: false

  alias OmniArchive.DuplicateIdentity
  alias OmniArchive.Ingestion.ExtractedImage
  import OmniArchive.DomainProfileTestHelper

  describe "fingerprint builder" do
    test "Archaeology で profile key + site + label から fingerprint を作る" do
      image = %ExtractedImage{site: " 新潟市中野遺跡 ", label: " FIG-1-1 "}

      assert DuplicateIdentity.fingerprint_for_image(image) ==
               "v1|archaeology|新潟市中野遺跡|fig-1-1"
    end

    test "空文字や nil を含む場合は fingerprint を作らない" do
      assert DuplicateIdentity.fingerprint_from_values("archaeology", "", "fig-1-1") == nil
      assert DuplicateIdentity.fingerprint_from_values("archaeology", "新潟市中野遺跡", nil) == nil
    end

    test "GeneralArchive で metadata-only field から fingerprint を作る" do
      put_domain_profile(OmniArchive.DomainProfiles.GeneralArchive)

      image = %ExtractedImage{
        label: " Photo-001 ",
        metadata: %{"collection" => " 広報写真アーカイブ "}
      }

      assert DuplicateIdentity.fingerprint_for_image(image) ==
               "v1|general_archive|広報写真アーカイブ|photo-001"
    end
  end
end
