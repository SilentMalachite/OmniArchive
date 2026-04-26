defmodule OmniArchiveWeb.ApprovalLiveTest do
  use OmniArchiveWeb.ConnCase, async: true

  setup :register_and_log_in_user

  describe "GET /lab/approval" do
    test "ログイン済みユーザーでも使えない", %{conn: conn} do
      conn = get(conn, "/lab/approval")

      assert response(conn, 404) =~ "Not Found"
    end
  end
end
