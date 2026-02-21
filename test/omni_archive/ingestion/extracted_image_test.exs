defmodule OmniArchive.Ingestion.ExtractedImageTest do
  use OmniArchive.DataCase, async: true

  alias OmniArchive.Ingestion.ExtractedImage
  import OmniArchive.Factory

  describe "changeset/2" do
    test "有効な属性でチェンジセットが正常に作成される" do
      pdf_source = insert_pdf_source()

      attrs = %{
        pdf_source_id: pdf_source.id,
        page_number: 1,
        image_path: "priv/static/uploads/pages/1/page-001.png",
        caption: "テストキャプション",
        label: "fig-1-1"
      }

      changeset = ExtractedImage.changeset(%ExtractedImage{}, attrs)
      assert changeset.valid?
    end

    test "pdf_source_id と page_number が必須である" do
      changeset = ExtractedImage.changeset(%ExtractedImage{}, %{})
      refute changeset.valid?

      assert %{pdf_source_id: ["can't be blank"], page_number: ["can't be blank"]} =
               errors_on(changeset)
    end

    test "status のデフォルト値が draft である" do
      image = %ExtractedImage{}
      assert image.status == "draft"
    end

    test "有効な status 値を受け入れる" do
      pdf_source = insert_pdf_source()

      for status <- ["draft", "pending_review", "published"] do
        attrs = %{pdf_source_id: pdf_source.id, page_number: 1, status: status}
        changeset = ExtractedImage.changeset(%ExtractedImage{}, attrs)
        assert changeset.valid?, "status: #{status} は valid であるべき"
      end
    end

    test "無効な status 値を拒否する" do
      pdf_source = insert_pdf_source()
      attrs = %{pdf_source_id: pdf_source.id, page_number: 1, status: "archived"}
      changeset = ExtractedImage.changeset(%ExtractedImage{}, attrs)
      refute changeset.valid?
      assert %{status: _} = errors_on(changeset)
    end

    test "geometry を JSONB マップとして保存できる" do
      pdf_source = insert_pdf_source()

      attrs = %{
        pdf_source_id: pdf_source.id,
        page_number: 1,
        geometry: %{"x" => 10, "y" => 20, "width" => 200, "height" => 300}
      }

      changeset = ExtractedImage.changeset(%ExtractedImage{}, attrs)
      assert changeset.valid?

      assert Ecto.Changeset.get_change(changeset, :geometry) == %{
               "x" => 10,
               "y" => 20,
               "width" => 200,
               "height" => 300
             }
    end

    # --- label フォーマットバリデーション ---

    test "有効な label 形式 (fig-数字-数字) を受け入れる" do
      pdf_source = insert_pdf_source()

      for label <- ["fig-1-1", "fig-12-345", "fig-0-0"] do
        attrs = %{pdf_source_id: pdf_source.id, page_number: 1, label: label}
        changeset = ExtractedImage.changeset(%ExtractedImage{}, attrs)
        assert changeset.valid?, "label: #{label} は valid であるべき"
      end
    end

    test "無効な label 形式を拒否する" do
      pdf_source = insert_pdf_source()

      for label <- ["fig-001", "abc", "FIG-1-1", "fig1-1", "fig-1", "test"] do
        attrs = %{pdf_source_id: pdf_source.id, page_number: 1, label: label}
        changeset = ExtractedImage.changeset(%ExtractedImage{}, attrs)
        refute changeset.valid?, "label: #{label} は invalid であるべき"
        assert %{label: [msg]} = errors_on(changeset)
        assert msg =~ "fig-番号-番号"
      end
    end

    test "label が空文字の場合はフォーマット検証をスキップする" do
      pdf_source = insert_pdf_source()
      attrs = %{pdf_source_id: pdf_source.id, page_number: 1, label: ""}
      changeset = ExtractedImage.changeset(%ExtractedImage{}, attrs)
      assert changeset.valid?
    end

    test "label が nil の場合はフォーマット検証をスキップする" do
      pdf_source = insert_pdf_source()
      attrs = %{pdf_source_id: pdf_source.id, page_number: 1}
      changeset = ExtractedImage.changeset(%ExtractedImage{}, attrs)
      assert changeset.valid?
    end

    # --- 動的メタデータ (custom_metadata) 変換 ---

    test "custom_metadata_list (マップリスト) から custom_metadata (Map) へ変換される" do
      pdf_source = insert_pdf_source()

      # Phoenix の input フォーム風 (index が key の Map)
      metadata_list = %{
        "0" => %{"key" => "撮影者", "value" => "山田太郎"},
        "1" => %{"key" => "特記事項", "value" => "破損箇所あり"}
      }

      attrs = %{
        pdf_source_id: pdf_source.id,
        page_number: 1,
        custom_metadata_list: metadata_list
      }

      changeset = ExtractedImage.changeset(%ExtractedImage{}, attrs)
      assert changeset.valid?

      custom_metadata = Ecto.Changeset.get_change(changeset, :custom_metadata)

      assert custom_metadata == %{
               "撮影者" => "山田太郎",
               "特記事項" => "破損箇所あり"
             }
    end

    test "custom_metadata_list (配列リスト) から custom_metadata へ変換される" do
      pdf_source = insert_pdf_source()

      metadata_list = [
        %{"key" => "所有者", "value" => "博物館"},
        %{"key" => "色", "value" => "赤褐"}
      ]

      attrs = %{
        pdf_source_id: pdf_source.id,
        page_number: 1,
        custom_metadata_list: metadata_list
      }

      changeset = ExtractedImage.changeset(%ExtractedImage{}, attrs)
      assert changeset.valid?

      custom_metadata = Ecto.Changeset.get_change(changeset, :custom_metadata)

      assert custom_metadata == %{
               "所有者" => "博物館",
               "色" => "赤褐"
             }
    end

    test "custom_metadata_list で key が空の場合は除外される" do
      pdf_source = insert_pdf_source()

      metadata_list = [
        %{"key" => "有効なキー", "value" => "値１"},
        %{"key" => "", "value" => "無視される値"},
        %{"key" => "  ", "value" => "これも無視される"}
      ]

      attrs = %{
        pdf_source_id: pdf_source.id,
        page_number: 1,
        custom_metadata_list: metadata_list
      }

      changeset = ExtractedImage.changeset(%ExtractedImage{}, attrs)
      assert changeset.valid?

      custom_metadata = Ecto.Changeset.get_change(changeset, :custom_metadata)
      assert custom_metadata == %{"有効なキー" => "値１"}
    end
  end
end
