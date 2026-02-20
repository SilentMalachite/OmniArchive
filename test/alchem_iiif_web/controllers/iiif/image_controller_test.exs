defmodule AlchemIiifWeb.IIIF.ImageControllerTest do
  use AlchemIiifWeb.ConnCase, async: true

  import AlchemIiif.Factory

  describe "GET /iiif/image/:identifier/info.json" do
    test "存在しない identifier で 404 を返す", %{conn: conn} do
      conn = get(conn, ~p"/iiif/image/nonexistent/info.json")
      assert json_response(conn, 404)
      assert json_response(conn, 404)["error"] =~ "見つかりません"
    end
  end

  describe "GET /iiif/image/:identifier/:region/:size/:rotation/:quality" do
    test "存在しない identifier で 404 を返す", %{conn: conn} do
      conn = get(conn, "/iiif/image/nonexistent/full/max/0/default.jpg")
      assert json_response(conn, 404)
      assert json_response(conn, 404)["error"] =~ "見つかりません"
    end

    test "Manifest はあるが PTIF ファイルがない場合 404 を返す", %{conn: conn} do
      # PTIF パスは存在しないパスを設定
      manifest =
        insert_manifest(%{
          identifier: "img-no-ptif-test"
        })

      # ptif_path は関連する extracted_image に自動設定されるが、ファイルは存在しない
      conn = get(conn, "/iiif/image/#{manifest.identifier}/full/max/0/default.jpg")
      assert json_response(conn, 404)
    end
  end
end
