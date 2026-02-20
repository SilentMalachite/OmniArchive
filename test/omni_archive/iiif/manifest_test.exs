defmodule OmniArchive.IIIF.ManifestTest do
  use OmniArchive.DataCase, async: true

  alias OmniArchive.IIIF.Manifest
  import OmniArchive.Factory

  describe "changeset/2" do
    test "有効な属性でチェンジセットが正常に作成される" do
      image = insert_extracted_image()

      attrs = %{
        extracted_image_id: image.id,
        identifier: "img-test-001",
        metadata: %{
          "label" => %{"en" => ["Test"], "ja" => ["テスト"]},
          "summary" => %{"en" => ["Summary"], "ja" => ["概要"]}
        }
      }

      changeset = Manifest.changeset(%Manifest{}, attrs)
      assert changeset.valid?
    end

    test "extracted_image_id と identifier が必須である" do
      changeset = Manifest.changeset(%Manifest{}, %{})
      refute changeset.valid?

      errors = errors_on(changeset)
      assert "can't be blank" in errors.extracted_image_id
      assert "can't be blank" in errors.identifier
    end

    test "identifier が一意である" do
      image1 = insert_extracted_image()
      image2 = insert_extracted_image()

      # 最初の Manifest を挿入
      %Manifest{}
      |> Manifest.changeset(%{
        extracted_image_id: image1.id,
        identifier: "unique-id-001"
      })
      |> Repo.insert!()

      # 同じ identifier で2つめの Manifest を挿入すると失敗する
      {:error, changeset} =
        %Manifest{}
        |> Manifest.changeset(%{
          extracted_image_id: image2.id,
          identifier: "unique-id-001"
        })
        |> Repo.insert()

      assert %{identifier: _} = errors_on(changeset)
    end

    test "metadata のデフォルト値が空マップである" do
      manifest = %Manifest{}
      assert manifest.metadata == %{}
    end
  end
end
