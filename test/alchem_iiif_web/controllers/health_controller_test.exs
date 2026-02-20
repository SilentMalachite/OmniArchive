defmodule AlchemIiifWeb.HealthControllerTest do
  use AlchemIiifWeb.ConnCase, async: true

  describe "GET /api/health" do
    test "ヘルスチェックで正常なレスポンスを返す", %{conn: conn} do
      conn = get(conn, ~p"/api/health")
      assert json_response(conn, 200) == %{"status" => "ok", "app" => "alchem_iiif"}
    end

    test "Content-Type が JSON である", %{conn: conn} do
      conn = get(conn, ~p"/api/health")
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/json"
    end
  end
end
