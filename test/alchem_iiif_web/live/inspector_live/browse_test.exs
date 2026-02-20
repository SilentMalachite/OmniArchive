defmodule AlchemIiifWeb.InspectorLive.BrowseTest do
  @moduledoc """
  Browse LiveView のテスト。

  ウィザード Step 2 のページ閲覧・選択画面をテストします。
  マウント時の初期表示、select_page イベントでのダイレクトナビゲーション、
  エラーハンドリングを検証します。

  ## Lazy Creation ルート
  select_page はレコードを作成せず、ダイレクトに Crop 画面へ遷移します。
  ルート: /lab/inspector/:pdf_source_id/page/:page_number
  """
  use AlchemIiifWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import AlchemIiif.Factory

  setup :register_and_log_in_user

  describe "マウント" do
    test "正常な PDF Source でステップ2が表示される", %{conn: conn, user: user} do
      pdf_source = insert_pdf_source(%{status: "ready", user_id: user.id})

      # テスト用ページ画像ディレクトリを作成
      pages_dir = Path.join(["priv", "static", "uploads", "pages", "#{pdf_source.id}"])
      File.mkdir_p!(pages_dir)

      # ダミーのページ画像ファイルを作成
      File.write!(Path.join(pages_dir, "page-001.png"), "dummy")

      {:ok, _view, html} = live(conn, ~p"/lab/browse/#{pdf_source.id}")

      # ステップ2（ページ選択）が表示される
      assert html =~ "ページを選択してください"
      assert html =~ "ページ 1"
    after
      # テスト用ファイルをクリーンアップ
      File.rm_rf!("priv/static/uploads/pages")
    end

    test "存在しない PDF Source でリダイレクトされる", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/lab", flash: flash}}} =
               live(conn, ~p"/lab/browse/999999")

      assert flash["error"] =~ "指定されたPDFソースが見つかりません"
    end

    test "ページ画像がない場合に警告が表示される", %{conn: conn, user: user} do
      pdf_source = insert_pdf_source(%{status: "ready", user_id: user.id})

      {:ok, _view, html} = live(conn, ~p"/lab/browse/#{pdf_source.id}")

      assert html =~ "画像が見つかりませんでした"
    end

    test "エラーステータスの PDF Source でエラー画面が表示される", %{conn: conn, user: user} do
      pdf_source = insert_pdf_source(%{status: "error", user_id: user.id})

      {:ok, _view, html} = live(conn, ~p"/lab/browse/#{pdf_source.id}")

      assert html =~ "PDFの処理中にエラーが発生しました"
    end
  end

  describe "select_page イベント（ダイレクトナビゲーション）" do
    test "有効なページ番号でダイレクトに Crop 画面へ遷移する", %{conn: conn, user: user} do
      pdf_source = insert_pdf_source(%{status: "ready", user_id: user.id})

      # テスト用ページ画像ディレクトリ・ファイルを作成
      pages_dir = Path.join(["priv", "static", "uploads", "pages", "#{pdf_source.id}"])
      File.mkdir_p!(pages_dir)
      File.write!(Path.join(pages_dir, "page-001.png"), "dummy")

      {:ok, view, _html} = live(conn, ~p"/lab/browse/#{pdf_source.id}")

      # サムネイルクリック → ダイレクトに Crop 画面（Lazy Creation ルート）へ遷移
      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> element("button.page-thumbnail", "ページ 1")
               |> render_click()

      assert to =~ "/lab/inspector/#{pdf_source.id}/page/1"
    after
      File.rm_rf!("priv/static/uploads/pages")
    end

    test "無効なページ番号でエラーがハンドリングされる", %{conn: conn, user: user} do
      pdf_source = insert_pdf_source(%{status: "ready", user_id: user.id})
      pages_dir = Path.join(["priv", "static", "uploads", "pages", "#{pdf_source.id}"])
      File.mkdir_p!(pages_dir)
      File.write!(Path.join(pages_dir, "page-001.png"), "dummy")

      {:ok, view, _html} = live(conn, ~p"/lab/browse/#{pdf_source.id}")

      # 無効なページ番号を直接イベント送信 — クラッシュしないことを確認
      assert render_hook(view, "select_page", %{"page" => "invalid"}) =~ "ページを選択してください"
    after
      File.rm_rf!("priv/static/uploads/pages")
    end

    test "存在しないページ番号でエラーがハンドリングされる", %{conn: conn, user: user} do
      pdf_source = insert_pdf_source(%{status: "ready", user_id: user.id})
      pages_dir = Path.join(["priv", "static", "uploads", "pages", "#{pdf_source.id}"])
      File.mkdir_p!(pages_dir)
      File.write!(Path.join(pages_dir, "page-001.png"), "dummy")

      {:ok, view, _html} = live(conn, ~p"/lab/browse/#{pdf_source.id}")

      # 存在しないページ番号（999）を送信 — クラッシュしないことを確認
      assert render_hook(view, "select_page", %{"page" => "999"}) =~ "ページを選択してください"
    after
      File.rm_rf!("priv/static/uploads/pages")
    end
  end

  describe "ナビゲーション" do
    test "戻るリンクが Lab トップを指す", %{conn: conn, user: user} do
      pdf_source = insert_pdf_source(%{status: "ready", user_id: user.id})
      pages_dir = Path.join(["priv", "static", "uploads", "pages", "#{pdf_source.id}"])
      File.mkdir_p!(pages_dir)
      File.write!(Path.join(pages_dir, "page-001.png"), "dummy")

      {:ok, _view, html} = live(conn, ~p"/lab/browse/#{pdf_source.id}")

      assert html =~ "← 戻る"
      assert html =~ "/lab"
    after
      File.rm_rf!("priv/static/uploads/pages")
    end
  end
end
