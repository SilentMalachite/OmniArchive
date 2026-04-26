defmodule OmniArchiveWeb.LabLive.IndexTest do
  use OmniArchiveWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  describe "security: event parameter validation" do
    test "不正な ID の削除イベントでクラッシュしない", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/lab")

      html = render_click(view, "delete_project", %{"id" => "not-an-id"})

      assert html =~ "プロジェクト一覧"
    end

    test "不正な ID の提出イベントでクラッシュしない", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/lab")

      html = render_click(view, "submit_project", %{"id" => "not-an-id"})

      assert html =~ "プロジェクト一覧"
    end
  end
end
