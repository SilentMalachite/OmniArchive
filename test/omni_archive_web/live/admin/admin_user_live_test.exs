defmodule OmniArchiveWeb.Admin.AdminUserLiveTest do
  use OmniArchiveWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    user = OmniArchive.AccountsFixtures.admin_fixture()
    conn = OmniArchiveWeb.ConnCase.log_in_user(conn, user)
    %{conn: conn}
  end

  describe "security: event parameter validation" do
    test "不正な ID の削除イベントでクラッシュしない", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      html = render_click(view, "delete", %{"id" => "not-an-id"})

      assert html =~ "ユーザーが見つかりません"
    end
  end
end
