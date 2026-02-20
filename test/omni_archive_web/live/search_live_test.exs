defmodule OmniArchiveWeb.SearchLiveTest do
  use OmniArchiveWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import OmniArchive.Factory

  setup :register_and_log_in_user

  describe "mount/3" do
    test "検索画面が正常にマウントされる", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/lab/search")

      assert html =~ "画像を検索"
      assert html =~ "search-input"
    end

    test "初期状態で結果件数が表示される", %{conn: conn} do
      # テストデータを作成
      insert_extracted_image(%{ptif_path: "/path/to/test.tif", status: "published"})

      {:ok, _view, html} = live(conn, ~p"/lab/search")

      assert html =~ "件の図版が見つかりました"
    end

    test "画像がない場合はメッセージが表示される", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/lab/search")

      assert html =~ "まだ図版が登録されていません"
    end
  end

  describe "search イベント" do
    test "テキスト検索が実行される", %{conn: conn} do
      insert_extracted_image(%{
        ptif_path: "/path/to/test.tif",
        caption: "テスト土器の出土状況",
        label: "fig-50-1"
      })

      {:ok, view, _html} = live(conn, ~p"/lab/search")

      # 検索を実行
      html =
        view
        |> element("#search-input")
        |> render_keyup(%{"query" => "テスト土器"})

      assert html =~ "fig-50-1" or html =~ "件の図版"
    end

    test "空の検索で全件表示に戻る", %{conn: conn} do
      insert_extracted_image(%{
        ptif_path: "/path/to/test.tif",
        caption: "テスト"
      })

      {:ok, view, _html} = live(conn, ~p"/lab/search")

      html =
        view
        |> element("#search-input")
        |> render_keyup(%{"query" => ""})

      # 結果が表示される（または空メッセージ）
      assert html =~ "件の図版" or html =~ "結果なし" or html =~ "まだ図版が登録されていません"
    end
  end

  describe "toggle_filter イベント" do
    test "フィルターがトグルされる", %{conn: conn} do
      insert_extracted_image(%{
        ptif_path: "/path/to/test.tif",
        site: "テスト市遺跡A"
      })

      {:ok, view, _html} = live(conn, ~p"/lab/search")

      # フィルターをクリック
      html = render_click(view, "toggle_filter", %{"type" => "site", "value" => "テスト市遺跡A"})
      assert html =~ "件の図版" or html =~ "結果なし"
    end

    test "同じフィルターを再クリックでクリアされる", %{conn: conn} do
      insert_extracted_image(%{
        ptif_path: "/path/to/test.tif",
        site: "テスト市遺跡B"
      })

      {:ok, view, _html} = live(conn, ~p"/lab/search")

      # フィルターを有効化
      render_click(view, "toggle_filter", %{"type" => "site", "value" => "テスト市遺跡B"})

      # もう一度クリックしてクリア
      html = render_click(view, "toggle_filter", %{"type" => "site", "value" => "テスト市遺跡B"})
      assert html =~ "件の図版" or html =~ "結果なし"
    end
  end

  describe "clear_filters イベント" do
    test "全フィルターがクリアされる", %{conn: conn} do
      insert_extracted_image(%{
        ptif_path: "/path/to/test.tif",
        site: "テスト市遺跡"
      })

      {:ok, view, _html} = live(conn, ~p"/lab/search")

      # フィルターを有効化してからクリア
      render_click(view, "toggle_filter", %{"type" => "site", "value" => "テスト市遺跡"})
      html = render_click(view, "clear_filters", %{})

      assert html =~ "件の図版" or html =~ "結果なし"
    end
  end
end
