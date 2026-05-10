defmodule OmniArchiveWeb.StorageKeyPathsTest do
  use OmniArchiveWeb.ConnCase, async: false

  import OmniArchive.Factory
  import Phoenix.LiveViewTest

  alias OmniArchive.Ingestion.PdfSource
  alias OmniArchiveWeb.UploadUrls

  setup :register_and_log_in_user

  describe "storage_key backed page directories" do
    test "Browse reads pages from PdfSource.pages_dir/1", %{conn: conn, user: user} do
      pdf_source = insert_pdf_source(%{status: "ready", user_id: user.id})
      page_path = write_storage_key_page(pdf_source)

      {:ok, _view, html} = live(conn, ~p"/lab/browse/#{pdf_source.id}")

      assert page_path =~ pdf_source.storage_key
      assert html =~ "ページ 1"
      assert html =~ ~s(src="/lab/uploads/pages/#{pdf_source.id}/page-001.png")
      refute html =~ "画像が見つかりませんでした"
    end

    test "Crop reads pages from PdfSource.pages_dir/1", %{conn: conn, user: user} do
      pdf_source = insert_pdf_source(%{status: "ready", user_id: user.id})
      write_storage_key_page(pdf_source)

      {:ok, _view, html} = live(conn, ~p"/lab/crop/#{pdf_source.id}/1")

      assert html =~ ~s(id="inspect-target")
      assert html =~ ~s(src="/lab/uploads/pages/#{pdf_source.id}/page-001.png")
    end

    test "UploadUrls maps storage_key image paths back to the PdfSource id route", %{user: user} do
      pdf_source = insert_pdf_source(%{status: "ready", user_id: user.id})
      page_path = write_storage_key_page(pdf_source)

      assert UploadUrls.page_image_url(page_path) ==
               "/lab/uploads/pages/#{pdf_source.id}/page-001.png"
    end

    test "authenticated page delivery still serves legacy id directories", %{
      conn: conn,
      user: user
    } do
      pdf_source = insert_pdf_source(%{status: "ready", user_id: user.id})
      legacy_dir = legacy_pages_dir(pdf_source)
      File.mkdir_p!(legacy_dir)
      File.write!(Path.join(legacy_dir, "page-001.png"), "legacy page")

      on_exit(fn -> cleanup_page_dirs(pdf_source) end)

      conn = get(conn, "/lab/uploads/pages/#{pdf_source.id}/page-001.png")

      assert response(conn, 200) == "legacy page"
    end
  end

  defp write_storage_key_page(%PdfSource{} = pdf_source) do
    storage_dir = storage_key_pages_dir(pdf_source)
    File.mkdir_p!(storage_dir)
    page_path = Path.join(storage_dir, "page-001.png")
    File.write!(page_path, "page")

    on_exit(fn -> cleanup_page_dirs(pdf_source) end)

    page_path
  end

  defp storage_key_pages_dir(%PdfSource{storage_key: storage_key}) do
    Path.join(["priv", "static", "uploads", "pages", storage_key])
  end

  defp legacy_pages_dir(%PdfSource{id: id}) do
    Path.join(["priv", "static", "uploads", "pages", "#{id}"])
  end

  defp cleanup_page_dirs(%PdfSource{} = pdf_source) do
    File.rm_rf(storage_key_pages_dir(pdf_source))
    File.rm_rf(legacy_pages_dir(pdf_source))
  end
end
