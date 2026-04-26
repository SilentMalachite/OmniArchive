defmodule OmniArchiveWeb.IIIF.ImageControllerTest do
  use OmniArchiveWeb.ConnCase, async: false

  import OmniArchive.Factory
  import OmniArchive.DomainProfileTestHelper

  setup do
    put_domain_profile(OmniArchive.DomainProfiles.Archaeology)
    :ok
  end

  describe "GET /iiif/image/:identifier/info.json" do
    test "存在しない identifier で 404 を返す", %{conn: conn} do
      conn = get(conn, ~p"/iiif/image/nonexistent/info.json")
      assert json_response(conn, 404)
      assert json_response(conn, 404)["error"] =~ "見つかりません"
    end

    test "published ではない画像の Manifest は 404 を返す", %{conn: conn} do
      manifest = insert_manifest_for_status("draft")

      conn = get(conn, ~p"/iiif/image/#{manifest.identifier}/info.json")

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

    test "published ではない画像のタイルは 404 を返す", %{conn: conn} do
      manifest = insert_manifest_for_status("pending_review")

      conn = get(conn, "/iiif/image/#{manifest.identifier}/full/max/0/default.jpg")

      assert json_response(conn, 404)
      assert json_response(conn, 404)["error"] =~ "見つかりません"
    end

    test "不正な region は 400 を返す", %{conn: conn} do
      manifest = insert_manifest_for_status("published")

      conn = get(conn, "/iiif/image/#{manifest.identifier}/abc,0,100,100/max/0/default.jpg")

      assert json_response(conn, 400)
      assert json_response(conn, 400)["error"] =~ "不正な画像リクエスト"
    end

    test "不正な size は 400 を返す", %{conn: conn} do
      manifest = insert_manifest_for_status("published")

      conn = get(conn, "/iiif/image/#{manifest.identifier}/full/999999,/0/default.jpg")

      assert json_response(conn, 400)
      assert json_response(conn, 400)["error"] =~ "不正な画像リクエスト"
    end

    test "不正な rotation は 400 を返す", %{conn: conn} do
      manifest = insert_manifest_for_status("published")

      conn = get(conn, "/iiif/image/#{manifest.identifier}/full/max/45/default.jpg")

      assert json_response(conn, 400)
      assert json_response(conn, 400)["error"] =~ "不正な画像リクエスト"
    end

    test "不正な format は 400 を返す", %{conn: conn} do
      manifest = insert_manifest_for_status("published")

      conn = get(conn, "/iiif/image/#{manifest.identifier}/full/max/0/default.gif")

      assert json_response(conn, 400)
      assert json_response(conn, 400)["error"] =~ "不正な画像リクエスト"
    end
  end

  defp insert_manifest_for_status(status) do
    ptif_path = test_ptif_path(status)
    File.mkdir_p!(Path.dirname(ptif_path))
    File.write!(ptif_path, "test")

    image =
      insert_extracted_image(%{
        status: status,
        ptif_path: ptif_path
      })

    insert_manifest(%{
      identifier: "img-sec006-#{status}-#{System.unique_integer([:positive])}",
      extracted_image_id: image.id
    })
  end

  defp test_ptif_path(status) do
    Path.join([
      System.tmp_dir!(),
      "omni_archive_iiif_controller_test",
      "#{status}-#{System.unique_integer([:positive])}.ptif"
    ])
  end
end
