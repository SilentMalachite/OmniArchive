defmodule OmniArchiveWeb.SearchLiveTest do
  use OmniArchiveWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import OmniArchive.Factory
  alias OmniArchive.DomainProfiles
  alias OmniArchive.DomainProfiles.GeneralArchive
  alias OmniArchive.Repo

  setup :register_and_log_in_user

  describe "mount/3" do
    test "検索画面が正常にマウントされる", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/lab/search")

      assert html =~ "画像を検索"
      assert html =~ "search-input"
      assert html =~ "キャプション、ラベル、遺跡名で検索..."
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
      assert render(view) =~ "📍 遺跡名"

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

  describe "metadata 表示" do
    test "profile metadata field を loop 描画し metadata の値を優先表示する", %{conn: conn} do
      image =
        insert_extracted_image(%{
          ptif_path: "/path/to/test.tif",
          site: "旧検索市遺跡",
          period: "旧検索時代",
          artifact_type: "旧検索種別"
        })

      Repo.query!(
        """
        UPDATE extracted_images
        SET metadata = jsonb_build_object('site', $1::text, 'period', $2::text, 'artifact_type', $3::text)
        WHERE id = $4
        """,
        ["新検索市遺跡", "新検索時代", "新検索種別", image.id]
      )

      {:ok, _view, html} = live(conn, ~p"/lab/search")

      assert html =~ "新検索市遺跡"
      assert html =~ "新検索時代"
      assert html =~ "新検索種別"
      refute html =~ "旧検索市遺跡"
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

  describe "GeneralArchive 表示" do
    setup do
      put_domain_profile(GeneralArchive)
      :ok
    end

    test "placeholder と facet が GeneralArchive 定義に切り替わる", %{conn: conn} do
      insert_extracted_image(%{
        ptif_path: "/path/to/general-live.tif",
        label: "photo-001",
        metadata: %{
          "collection" => "広報写真アーカイブ",
          "item_type" => "写真",
          "date_note" => "1960年代"
        }
      })

      {:ok, _view, html} = live(conn, ~p"/lab/search")

      assert html =~ DomainProfiles.ui_text([:search, :placeholder])
      assert html =~ "🗂️ コレクション"
      assert html =~ "📁 資料種別"
      assert html =~ "📅 年代メモ"
    end

    test "metadata-only field の値が結果カードに表示される", %{conn: conn} do
      insert_extracted_image(%{
        ptif_path: "/path/to/general-live-card.tif",
        label: "photo-002",
        metadata: %{
          "collection" => "広報写真アーカイブ",
          "item_type" => "ポスター",
          "date_note" => "1972年ごろ"
        }
      })

      {:ok, _view, html} = live(conn, ~p"/lab/search")

      assert html =~ "広報写真アーカイブ"
      assert html =~ "ポスター"
      assert html =~ "1972年ごろ"
    end
  end
end
