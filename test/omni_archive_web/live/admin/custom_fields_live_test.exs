defmodule OmniArchiveWeb.Admin.CustomFieldsLiveTest do
  use OmniArchiveWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import OmniArchive.DomainProfileTestHelper

  setup %{conn: conn} do
    put_domain_profile(OmniArchive.DomainProfiles.GeneralArchive)
    user = OmniArchive.AccountsFixtures.admin_fixture()
    conn = OmniArchiveWeb.ConnCase.log_in_user(conn, user)
    %{conn: conn}
  end

  describe "security: event parameter validation" do
    test "不正な ID の編集イベントでクラッシュしない", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/fields")

      html = render_click(view, "edit_field", %{"id" => "not-an-id"})

      assert html =~ "フィールドを選択できません"
    end

    test "不正な ID の有効化切替イベントでクラッシュしない", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/fields")

      html = render_click(view, "toggle_active", %{"id" => "not-an-id"})

      assert html =~ "フィールドを更新できません"
    end

    test "不正な ID の並び替えイベントでクラッシュしない", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/fields")

      html = render_click(view, "move_up", %{"id" => "not-an-id"})

      assert html =~ "フィールドを並び替えできません"
    end

    test "不正な ID の削除イベントでクラッシュしない", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/fields")

      html = render_click(view, "delete_field", %{"id" => "not-an-id"})

      assert html =~ "フィールドを削除できません"
    end
  end
end
