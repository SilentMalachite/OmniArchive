defmodule OmniArchiveWeb.Admin.AdminTrashLiveTest do
  use OmniArchiveWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    user = OmniArchive.AccountsFixtures.admin_fixture()
    conn = OmniArchiveWeb.ConnCase.log_in_user(conn, user)
    %{conn: conn}
  end

  describe "security: event parameter validation" do
    test "不正な ID の復元イベントでクラッシュしない", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/trash")

      html = render_click(view, "restore", %{"id" => "not-an-id"})

      assert html =~ "復元に失敗しました"
    end

    test "不正な ID の完全削除イベントでクラッシュしない", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/trash")

      html = render_click(view, "destroy", %{"id" => "not-an-id"})

      assert html =~ "完全削除に失敗しました"
    end
  end
end
