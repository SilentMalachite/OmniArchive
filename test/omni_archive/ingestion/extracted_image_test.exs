defmodule OmniArchive.Ingestion.ExtractedImageTest do
  use OmniArchive.DataCase, async: true

  alias OmniArchive.Ingestion.ExtractedImage
  alias OmniArchive.Ingestion.ExtractedImageMetadata
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

    test "検索用メタデータフィールドが保存される" do
      pdf_source = insert_pdf_source()

      attrs = %{
        pdf_source_id: pdf_source.id,
        page_number: 1,
        site: "吉野ヶ里町遺跡",
        period: "弥生時代",
        artifact_type: "銅鐸"
      }

      changeset = ExtractedImage.changeset(%ExtractedImage{}, attrs)
      assert changeset.valid?

      assert Ecto.Changeset.get_change(changeset, :metadata) == %{
               "site" => "吉野ヶ里町遺跡",
               "period" => "弥生時代",
               "artifact_type" => "銅鐸"
             }
    end

    test "metadata を旧カラムへ dual-write する" do
      pdf_source = insert_pdf_source()

      attrs = %{
        pdf_source_id: pdf_source.id,
        page_number: 1,
        metadata: %{"site" => "新潟市中野遺跡", "period" => "縄文時代", "artifact_type" => "土器"}
      }

      changeset = ExtractedImage.changeset(%ExtractedImage{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :site) == "新潟市中野遺跡"
      assert Ecto.Changeset.get_change(changeset, :period) == "縄文時代"
      assert Ecto.Changeset.get_change(changeset, :artifact_type) == "土器"
    end

    test "metadata_value は metadata 優先で旧カラムに fallback する" do
      image = %ExtractedImage{
        site: "旧遺跡",
        period: "旧時代",
        artifact_type: "旧種別",
        metadata: %{"site" => "新遺跡", "artifact_type" => "新種別"}
      }

      assert ExtractedImageMetadata.read(image, :site) == "新遺跡"
      assert ExtractedImageMetadata.read(image, :period) == "旧時代"
      assert ExtractedImageMetadata.read(image, :artifact_type) == "新種別"
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

    # --- 市町村バリデーション ---

    test "有効な site（市町村を含む）を受け入れる" do
      pdf_source = insert_pdf_source()

      for site <- ["新潟市中野遺跡", "吉野ヶ里町遺跡", "飛鳥村遺跡"] do
        attrs = %{pdf_source_id: pdf_source.id, page_number: 1, site: site}
        changeset = ExtractedImage.changeset(%ExtractedImage{}, attrs)
        assert changeset.valid?, "site: #{site} は valid であるべき"
      end
    end

    test "市町村を含まない site を拒否する" do
      pdf_source = insert_pdf_source()
      attrs = %{pdf_source_id: pdf_source.id, page_number: 1, site: "テスト遺跡"}
      changeset = ExtractedImage.changeset(%ExtractedImage{}, attrs)
      refute changeset.valid?
      assert %{site: [msg]} = errors_on(changeset)
      assert msg =~ "市町村名"
    end

    test "site が空文字の場合は市町村検証をスキップする" do
      pdf_source = insert_pdf_source()
      attrs = %{pdf_source_id: pdf_source.id, page_number: 1, site: ""}
      changeset = ExtractedImage.changeset(%ExtractedImage{}, attrs)
      assert changeset.valid?
    end

    # --- 文字数制限バリデーション (30文字) ---

    test "31文字の site を拒否する" do
      pdf_source = insert_pdf_source()
      # 31文字の文字列（市町村を含む）
      long_site = "新潟市" <> String.duplicate("あ", 28)
      attrs = %{pdf_source_id: pdf_source.id, page_number: 1, site: long_site}
      changeset = ExtractedImage.changeset(%ExtractedImage{}, attrs)
      refute changeset.valid?
      assert %{site: [msg]} = errors_on(changeset)
      assert msg =~ "30文字以内"
    end

    test "31文字の period を拒否する" do
      pdf_source = insert_pdf_source()
      long_period = String.duplicate("あ", 31)
      attrs = %{pdf_source_id: pdf_source.id, page_number: 1, period: long_period}
      changeset = ExtractedImage.changeset(%ExtractedImage{}, attrs)
      refute changeset.valid?
      assert %{period: [msg]} = errors_on(changeset)
      assert msg =~ "30文字以内"
    end

    test "31文字の artifact_type を拒否する" do
      pdf_source = insert_pdf_source()
      long_type = String.duplicate("あ", 31)
      attrs = %{pdf_source_id: pdf_source.id, page_number: 1, artifact_type: long_type}
      changeset = ExtractedImage.changeset(%ExtractedImage{}, attrs)
      refute changeset.valid?
      assert %{artifact_type: [msg]} = errors_on(changeset)
      assert msg =~ "30文字以内"
    end

    test "30文字以内のメタデータフィールドは受け入れられる" do
      pdf_source = insert_pdf_source()

      attrs = %{
        pdf_source_id: pdf_source.id,
        page_number: 1,
        site: "新潟市" <> String.duplicate("あ", 27),
        period: String.duplicate("あ", 30),
        artifact_type: String.duplicate("あ", 30)
      }

      changeset = ExtractedImage.changeset(%ExtractedImage{}, attrs)
      assert changeset.valid?
    end
  end
end
