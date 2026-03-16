defmodule OmniArchive.Ingestion.ExtractedImageDedupeTest do
  use OmniArchive.DataCase, async: false

  alias OmniArchive.Ingestion.ExtractedImage
  import OmniArchive.DomainProfileTestHelper
  import OmniArchive.Factory

  describe "changeset / unique constraint" do
    test "Archaeology で dedupe_fingerprint を自動計算する" do
      pdf_source = insert_pdf_source()

      changeset =
        ExtractedImage.changeset(%ExtractedImage{}, %{
          pdf_source_id: pdf_source.id,
          page_number: 1,
          site: "新潟市中野遺跡",
          label: "fig-1-1"
        })

      assert Ecto.Changeset.get_change(changeset, :dedupe_fingerprint) ==
               "v1|archaeology|新潟市中野遺跡|fig-1-1"
    end

    test "GeneralArchive の metadata-only field でも dedupe_fingerprint を自動計算する" do
      put_domain_profile(OmniArchive.DomainProfiles.GeneralArchive)
      pdf_source = insert_pdf_source()

      changeset =
        ExtractedImage.changeset(%ExtractedImage{}, %{
          pdf_source_id: pdf_source.id,
          page_number: 1,
          label: "photo-001",
          metadata: %{"collection" => "広報写真アーカイブ"}
        })

      assert Ecto.Changeset.get_change(changeset, :dedupe_fingerprint) ==
               "v1|general_archive|広報写真アーカイブ|photo-001"
    end

    test "同じ fingerprint の保存は unique constraint で拒否する" do
      pdf_source = insert_pdf_source()

      insert_extracted_image(%{
        pdf_source_id: pdf_source.id,
        site: "新潟市中野遺跡",
        label: "fig-1-1"
      })

      assert {:error, changeset} =
               %ExtractedImage{}
               |> ExtractedImage.changeset(%{
                 pdf_source_id: pdf_source.id,
                 page_number: 2,
                 site: "新潟市中野遺跡",
                 label: "fig-1-1"
               })
               |> OmniArchive.Repo.insert()

      assert %{dedupe_fingerprint: [msg]} = errors_on(changeset)
      assert msg =~ "この遺跡でそのラベルは既に登録されています"
    end

    test "deleted レコードと同じ fingerprint は再利用できる" do
      pdf_source = insert_pdf_source()

      insert_extracted_image(%{
        pdf_source_id: pdf_source.id,
        site: "新潟市中野遺跡",
        label: "fig-1-1",
        status: "deleted"
      })

      assert {:ok, _image} =
               %ExtractedImage{}
               |> ExtractedImage.changeset(%{
                 pdf_source_id: pdf_source.id,
                 page_number: 2,
                 site: "新潟市中野遺跡",
                 label: "fig-1-1"
               })
               |> OmniArchive.Repo.insert()
    end

    test "scope または label が空なら fingerprint は nil になる" do
      pdf_source = insert_pdf_source()

      changeset =
        ExtractedImage.changeset(%ExtractedImage{}, %{
          pdf_source_id: pdf_source.id,
          page_number: 1,
          label: "",
          site: "新潟市中野遺跡"
        })

      assert Ecto.Changeset.get_change(changeset, :dedupe_fingerprint) == nil
    end
  end
end
