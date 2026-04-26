defmodule OmniArchiveWeb.InspectorLive.CropTest do
  use OmniArchiveWeb.ConnCase, async: false

  import OmniArchive.Factory
  import Phoenix.LiveViewTest

  alias OmniArchive.Ingestion.ExtractedImage
  alias OmniArchive.Repo

  setup :register_and_log_in_user

  describe "mount/3 parameter validation" do
    test "不正な PDF Source ID では Lab に戻る", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/lab", flash: flash}}} =
               live(conn, ~p"/lab/crop/not-an-id/1")

      assert flash["error"] =~ "指定されたPDFソースが見つかりません"
    end

    test "不正な page_number では Lab に戻る", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/lab", flash: flash}}} =
               live(conn, ~p"/lab/crop/1/not-a-page")

      assert flash["error"] =~ "指定されたページが見つかりません"
    end
  end

  describe "geometry validation" do
    setup %{conn: conn, user: user} do
      pdf_source = insert_pdf_source(%{status: "ready", user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/lab/crop/#{pdf_source.id}/1")

      %{view: view, pdf_source: pdf_source}
    end

    test "頂点数が多すぎる polygon は保存しない", %{view: view} do
      points = for n <- 0..64, do: %{"x" => n, "y" => n}

      render_hook(view, "save_crop", %{"points" => points})

      assert Repo.aggregate(ExtractedImage, :count, :id) == 0
    end

    test "座標範囲外の polygon は保存しない", %{view: view} do
      points = [
        %{"x" => 0, "y" => 0},
        %{"x" => 20_001, "y" => 0},
        %{"x" => 10, "y" => 10}
      ]

      render_hook(view, "save_crop", %{"points" => points})

      assert Repo.aggregate(ExtractedImage, :count, :id) == 0
    end

    test "巨大な矩形 geometry は保存しない", %{view: view} do
      render_hook(view, "save_crop", %{
        "x" => "0",
        "y" => "0",
        "width" => "20001",
        "height" => "10"
      })

      assert Repo.aggregate(ExtractedImage, :count, :id) == 0
    end
  end
end
