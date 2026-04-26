defmodule OmniArchiveWeb.DownloadControllerTest do
  use OmniArchiveWeb.ConnCase, async: false

  describe "GET /download/:id" do
    test "不正な ID は 404 を返す", %{conn: conn} do
      conn = get(conn, ~p"/download/not-an-id")

      assert response(conn, 404) =~ "画像が見つかりません"
    end
  end
end
