defmodule OmniArchiveWeb.LabLive.ShowTest do
  use OmniArchiveWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  describe "mount/3 parameter validation" do
    test "不正な ID では Lab に戻る", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/lab", flash: flash}}} =
               live(conn, ~p"/lab/projects/not-an-id")

      assert flash["error"] =~ "プロジェクトが見つかりません"
    end
  end
end
