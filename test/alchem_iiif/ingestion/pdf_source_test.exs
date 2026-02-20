defmodule AlchemIiif.Ingestion.PdfSourceTest do
  use AlchemIiif.DataCase, async: true

  alias AlchemIiif.Ingestion.PdfSource

  describe "changeset/2" do
    test "有効な属性でチェンジセットが正常に作成される" do
      attrs = %{filename: "report.pdf", page_count: 5, status: "ready"}
      changeset = PdfSource.changeset(%PdfSource{}, attrs)
      assert changeset.valid?
    end

    test "filename が必須である" do
      attrs = %{page_count: 5}
      changeset = PdfSource.changeset(%PdfSource{}, attrs)
      refute changeset.valid?
      assert %{filename: ["can't be blank"]} = errors_on(changeset)
    end

    test "status のデフォルト値が uploading である" do
      pdf_source = %PdfSource{}
      assert pdf_source.status == "uploading"
    end

    test "有効な status 値を受け入れる" do
      for status <- ["uploading", "converting", "ready", "error"] do
        attrs = %{filename: "test.pdf", status: status}
        changeset = PdfSource.changeset(%PdfSource{}, attrs)
        assert changeset.valid?, "status: #{status} は valid であるべき"
      end
    end

    test "無効な status 値を拒否する" do
      attrs = %{filename: "test.pdf", status: "invalid_status"}
      changeset = PdfSource.changeset(%PdfSource{}, attrs)
      refute changeset.valid?
      assert %{status: _} = errors_on(changeset)
    end
  end
end
