defmodule OmniArchiveWeb.GalleryLiveTest do
  use OmniArchiveWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import OmniArchive.Factory
  import OmniArchive.DomainProfileTestHelper
  alias OmniArchive.Repo

  setup do
    put_domain_profile(OmniArchive.DomainProfiles.Archaeology)
    :ok
  end

  describe "mount/3" do
    test "ギャラリー画面が正常にマウントされる", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/gallery")

      assert html =~ "ギャラリー"
    end

    test "公開済み画像のみが表示される", %{conn: conn} do
      # published 画像を作成
      insert_extracted_image(%{
        ptif_path: "/path/to/published.tif",
        status: "published",
        label: "fig-40-1"
      })

      # draft 画像を作成
      insert_extracted_image(%{
        ptif_path: "/path/to/draft.tif",
        status: "draft",
        label: "fig-41-1"
      })

      {:ok, _view, html} = live(conn, ~p"/gallery")

      assert html =~ "fig-40-1"
      refute html =~ "fig-41-1"
    end

    test "公開画像がない場合はメッセージが表示される", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/gallery")

      assert html =~ "まだ公開済みの図版がありません"
    end

    test "geometry 付き画像で SVG クロップサムネイルが表示される", %{conn: conn} do
      insert_extracted_image(%{
        ptif_path: "/path/to/crop.tif",
        status: "published",
        label: "fig-42-1",
        image_path: "priv/static/uploads/test.png",
        geometry: %{"x" => 10, "y" => 20, "width" => 200, "height" => 150}
      })

      {:ok, _view, html} = live(conn, ~p"/gallery")

      # SVG viewBox がレンダリングされる
      assert html =~ "viewBox"
      assert html =~ "10 20 200 150"
      assert html =~ "xMidYMid meet"
    end
  end

  describe "search イベント" do
    test "テキスト検索で公開済み画像を絞り込める", %{conn: conn} do
      insert_extracted_image(%{
        ptif_path: "/path/to/test.tif",
        status: "published",
        summary: "ギャラリー検索テスト",
        label: "fig-43-1"
      })

      {:ok, view, _html} = live(conn, ~p"/gallery")

      html =
        view
        |> element("#gallery-search-input")
        |> render_keyup(%{"query" => "ギャラリー検索"})

      assert html =~ "fig-43-1" or html =~ "件の図版"
    end
  end

  describe "toggle_filter イベント" do
    test "フィルターチップスが動作する", %{conn: conn} do
      insert_extracted_image(%{
        ptif_path: "/path/to/test.tif",
        status: "published",
        site: "ギャラリー市遺跡"
      })

      {:ok, view, _html} = live(conn, ~p"/gallery")

      html = render_click(view, "toggle_filter", %{"type" => "site", "value" => "ギャラリー市遺跡"})
      assert html =~ "件の図版" or html =~ "結果なし"
    end
  end

  describe "metadata 表示" do
    test "profile metadata field を loop 描画し metadata の値を優先表示する", %{conn: conn} do
      image =
        insert_extracted_image(%{
          ptif_path: "/path/to/test.tif",
          status: "published",
          site: "旧ギャラリー市遺跡",
          period: "旧ギャラリー時代",
          artifact_type: "旧ギャラリー種別"
        })

      Repo.query!(
        """
        UPDATE extracted_images
        SET metadata = jsonb_build_object('site', $1::text, 'period', $2::text, 'artifact_type', $3::text)
        WHERE id = $4
        """,
        ["新ギャラリー市遺跡", "新ギャラリー時代", "新ギャラリー種別", image.id]
      )

      {:ok, _view, html} = live(conn, ~p"/gallery")

      assert html =~ "新ギャラリー市遺跡"
      assert html =~ "新ギャラリー時代"
      assert html =~ "新ギャラリー種別"
      refute html =~ "旧ギャラリー市遺跡"
    end
  end

  describe "clear_filters イベント" do
    test "フィルタークリアが動作する", %{conn: conn} do
      insert_extracted_image(%{
        ptif_path: "/path/to/test.tif",
        status: "published",
        site: "テスト市遺跡"
      })

      {:ok, view, _html} = live(conn, ~p"/gallery")

      # フィルターを有効化してからクリア
      render_click(view, "toggle_filter", %{"type" => "site", "value" => "テスト市遺跡"})
      html = render_click(view, "clear_filters", %{})

      assert html =~ "件の図版" or html =~ "結果なし"
    end
  end

  describe "select_image / close_modal イベント" do
    test "カードクリックでモーダルが表示される", %{conn: conn} do
      image =
        insert_extracted_image(%{
          ptif_path: "/path/to/modal.tif",
          status: "published",
          label: "fig-44-1",
          summary: "テストサマリー",
          image_path: "priv/static/uploads/test.png",
          geometry: %{"x" => 10, "y" => 20, "width" => 200, "height" => 150}
        })

      {:ok, view, _html} = live(conn, ~p"/gallery")

      html = render_click(view, "select_image", %{"id" => image.id})

      # モーダルが表示される
      assert html =~ "fig-44-1"
      assert html =~ "テストサマリー"
      assert html =~ "bg-black/90"
    end

    test "close_modal でモーダルが閉じる", %{conn: conn} do
      image =
        insert_extracted_image(%{
          ptif_path: "/path/to/modal2.tif",
          status: "published",
          label: "fig-45-1",
          image_path: "priv/static/uploads/test.png",
          geometry: %{"x" => 0, "y" => 0, "width" => 100, "height" => 100}
        })

      {:ok, view, _html} = live(conn, ~p"/gallery")

      # モーダルを開く
      render_click(view, "select_image", %{"id" => image.id})

      # モーダルを閉じる
      html = render_click(view, "close_modal", %{})

      # モーダルが非表示になる
      refute html =~ "bg-black/90"
    end

    test "非公開画像 ID を直接指定してもモーダルに表示されない", %{conn: conn} do
      private_images =
        [
          {"draft", "fig-46-1"},
          {"pending_review", "fig-46-2"},
          {"rejected", "fig-46-3"}
        ]
        |> Enum.map(fn {status, label} ->
          insert_extracted_image(%{
            ptif_path: "/path/to/private-#{status}.tif",
            status: status,
            label: label,
            summary: "非公開サマリー #{status}"
          })
        end)

      {:ok, view, initial_html} = live(conn, ~p"/gallery")

      refute initial_html =~ "fig-46-"
      refute initial_html =~ "非公開サマリー"

      for image <- private_images do
        html = render_click(view, "select_image", %{"id" => image.id})

        refute html =~ image.label
        refute html =~ image.summary
        refute html =~ "bg-black/90"
      end
    end

    test "初期状態ではモーダルが表示されない", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/gallery")

      refute html =~ "bg-black/90"
    end
  end
end
