defmodule OmniArchiveWeb.DownloadControllerTest do
  use OmniArchiveWeb.ConnCase, async: false

  import OmniArchive.Factory

  describe "GET /download/:id" do
    test "不正な ID は 404 を返す", %{conn: conn} do
      conn = get(conn, ~p"/download/not-an-id")

      assert response(conn, 404) =~ "画像が見つかりません"
    end

    test "公開済み画像は PNG ロスレスで配信される（image/png）", %{conn: conn} do
      pdf_source = insert_pdf_source()

      image =
        insert_extracted_image(%{
          pdf_source_id: pdf_source.id,
          status: "published",
          image_path: "priv/static/images/lab_wizard.png",
          geometry: %{"x" => 10, "y" => 10, "width" => 100, "height" => 100}
        })

      conn = get(conn, ~p"/download/#{image.id}")

      assert response(conn, 200)

      [content_type] = Plug.Conn.get_resp_header(conn, "content-type")
      assert content_type =~ "image/png"

      [content_disposition] = Plug.Conn.get_resp_header(conn, "content-disposition")
      assert content_disposition =~ ".png"
    end
  end
end
