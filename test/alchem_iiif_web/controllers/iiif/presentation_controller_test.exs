defmodule AlchemIiifWeb.IIIF.PresentationControllerTest do
  use AlchemIiifWeb.ConnCase, async: true

  import AlchemIiif.Factory

  describe "GET /iiif/presentation/:source_id/manifest" do
    test "公開済み画像の Manifest を JSON-LD で返す", %{conn: conn} do
      source = insert_pdf_source(%{filename: "report_2026.pdf"})

      # published 画像を2つ作成
      insert_extracted_image(%{
        pdf_source_id: source.id,
        page_number: 2,
        status: "published",
        label: "fig-2-1",
        geometry: %{"x" => 0, "y" => 0, "width" => 800, "height" => 600}
      })

      insert_extracted_image(%{
        pdf_source_id: source.id,
        page_number: 1,
        status: "published",
        label: "fig-1-1",
        geometry: %{"x" => 0, "y" => 0, "width" => 400, "height" => 300}
      })

      # draft 画像（含まれないはず）
      insert_extracted_image(%{
        pdf_source_id: source.id,
        page_number: 3,
        status: "draft",
        label: "fig-3-1"
      })

      conn = get(conn, "/iiif/presentation/#{source.id}/manifest")
      response = json_response(conn, 200)

      # IIIF 3.0 準拠の構造を検証
      assert response["@context"] == "http://iiif.io/api/presentation/3/context.json"
      assert response["type"] == "Manifest"
      assert response["label"] == %{"none" => ["report_2026.pdf"]}

      # published 画像のみ含まれる（draft は除外）
      assert length(response["items"]) == 2

      # page_number 昇順で並んでいる
      [canvas1, canvas2] = response["items"]
      assert canvas1["label"] == %{"none" => ["fig-1-1"]}
      assert canvas2["label"] == %{"none" => ["fig-2-1"]}

      # Canvas の寸法が geometry から取得されている
      assert canvas1["width"] == 400
      assert canvas1["height"] == 300
      assert canvas2["width"] == 800
      assert canvas2["height"] == 600

      # Canvas 構造の検証
      assert canvas1["type"] == "Canvas"
      assert is_list(canvas1["items"])

      annotation_page = hd(canvas1["items"])
      assert annotation_page["type"] == "AnnotationPage"

      annotation = hd(annotation_page["items"])
      assert annotation["type"] == "Annotation"
      assert annotation["motivation"] == "painting"
      assert annotation["body"]["type"] == "Image"
    end

    test "存在しない source_id で 404 を返す", %{conn: conn} do
      conn = get(conn, "/iiif/presentation/999999/manifest")
      assert json_response(conn, 404)
      assert json_response(conn, 404)["error"] =~ "見つかりません"
    end

    test "公開済み画像がない場合は空の items を返す", %{conn: conn} do
      source = insert_pdf_source()

      # draft のみ作成
      insert_extracted_image(%{
        pdf_source_id: source.id,
        page_number: 1,
        status: "draft"
      })

      conn = get(conn, "/iiif/presentation/#{source.id}/manifest")
      response = json_response(conn, 200)

      assert response["type"] == "Manifest"
      assert response["items"] == []
    end

    test "CORS ヘッダーが設定される", %{conn: conn} do
      source = insert_pdf_source()

      conn = get(conn, "/iiif/presentation/#{source.id}/manifest")
      assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
    end

    test "Content-Type が application/ld+json", %{conn: conn} do
      source = insert_pdf_source()

      conn = get(conn, "/iiif/presentation/#{source.id}/manifest")
      [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "application/ld+json"
    end

    test "geometry が nil の場合はデフォルト寸法を使用", %{conn: conn} do
      source = insert_pdf_source()

      insert_extracted_image(%{
        pdf_source_id: source.id,
        page_number: 1,
        status: "published",
        geometry: nil
      })

      conn = get(conn, "/iiif/presentation/#{source.id}/manifest")
      response = json_response(conn, 200)

      canvas = hd(response["items"])
      assert canvas["width"] == 1000
      assert canvas["height"] == 1000
    end
  end
end
