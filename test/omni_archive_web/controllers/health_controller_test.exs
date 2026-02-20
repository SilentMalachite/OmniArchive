defmodule OmniArchiveWeb.HealthControllerTest do
  use OmniArchiveWeb.ConnCase, async: true

  describe "GET /api/health" do
    test "ヘルスチェックで正常なレスポンスを返す", %{conn: conn} do
      conn = get(conn, ~p"/api/health")
      assert json_response(conn, 200) == %{"status" => "ok", "app" => "omni_archive"}
    end

    test "Content-Type が JSON である", %{conn: conn} do
      conn = get(conn, ~p"/api/health")
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/json"
    end
  end
end
