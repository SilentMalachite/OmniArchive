defmodule OmniArchiveWeb.Admin.DashboardLiveTest do
  use OmniArchiveWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    user = OmniArchive.AccountsFixtures.admin_fixture()
    conn = OmniArchiveWeb.ConnCase.log_in_user(conn, user)
    %{conn: conn}
  end

  describe "security: event parameter validation" do
    test "不正な ID の選択イベントでクラッシュしない", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/dashboard")

      html = render_click(view, "toggle_selection", %{"id" => "not-an-id"})

      assert html =~ "不正な画像 ID です"
    end

    test "不正な ID の削除イベントでクラッシュしない", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/dashboard")

      html = render_click(view, "delete", %{"id" => "not-an-id"})

      assert html =~ "画像を削除できません"
    end

    test "不正な ID の強制削除イベントでクラッシュしない", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/dashboard")

      html = render_click(view, "force_delete", %{"id" => "not-an-id"})

      assert html =~ "画像を削除できません"
    end
  end
end
