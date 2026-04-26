defmodule OmniArchiveWeb.StaticUploadsAccessTest do
  use OmniArchiveWeb.ConnCase, async: false

  import OmniArchive.Factory

  describe "GET /uploads/*path" do
    test "priv/static/uploads は直接配信されない", %{conn: conn} do
      upload_path = Path.join(["priv", "static", "uploads", "direct-access-test.txt"])
      File.mkdir_p!(Path.dirname(upload_path))
      File.write!(upload_path, "private upload")

      conn = get(conn, "/uploads/direct-access-test.txt")

      assert response(conn, 404) =~ "Not Found"
    after
      File.rm("priv/static/uploads/direct-access-test.txt")
    end
  end

  describe "GET /lab/uploads/pages/:pdf_source_id/:filename" do
    setup %{conn: conn} do
      user = OmniArchive.AccountsFixtures.user_fixture()
      pdf_source = insert_pdf_source(%{user_id: user.id, status: "ready"})
      pages_dir = Path.join(["priv", "static", "uploads", "pages", "#{pdf_source.id}"])
      File.mkdir_p!(pages_dir)
      File.write!(Path.join(pages_dir, "page-001.png"), "private page")

      on_exit(fn -> File.rm_rf!("priv/static/uploads/pages/#{pdf_source.id}") end)

      %{conn: log_in_user(conn, user), user: user, pdf_source: pdf_source}
    end

    test "所有者は認可付き経路からページ画像を取得できる", %{
      conn: conn,
      pdf_source: pdf_source
    } do
      conn = get(conn, "/lab/uploads/pages/#{pdf_source.id}/page-001.png")

      assert response(conn, 200) == "private page"
    end

    test "不正な PDF Source ID は 404", %{conn: conn} do
      conn = get(conn, "/lab/uploads/pages/not-an-id/page-001.png")

      assert response(conn, 404) =~ "Not Found"
    end

    test "他ユーザーはページ画像を取得できない", %{conn: _conn, pdf_source: pdf_source} do
      other_user = OmniArchive.AccountsFixtures.user_fixture()
      conn = build_conn() |> log_in_user(other_user)

      conn = get(conn, "/lab/uploads/pages/#{pdf_source.id}/page-001.png")

      assert response(conn, 404) =~ "Not Found"
    end
  end
end
