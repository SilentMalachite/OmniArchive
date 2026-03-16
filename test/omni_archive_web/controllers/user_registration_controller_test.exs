defmodule OmniArchiveWeb.UserRegistrationControllerTest do
  use OmniArchiveWeb.ConnCase, async: true

  # 招待制に移行したため /users/register ルートはコメントアウト済み。
  # ~p sigil はコンパイル時にルート検証を行い warning が出るため、
  # 通常の文字列リテラルを使用しています。
  @moduletag :skip

  import OmniArchive.AccountsFixtures

  describe "GET /users/register" do
    test "renders registration page", %{conn: conn} do
      conn = get(conn, "/users/register")
      response = html_response(conn, 200)
      assert response =~ "アカウント登録"
      assert response =~ "/users/log-in"
      assert response =~ "/users/register"
    end

    test "redirects if already logged in", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get("/users/register")

      assert redirected_to(conn) == "/"
    end
  end

  describe "POST /users/register" do
    @tag :capture_log
    test "creates account and logs the user in", %{conn: conn} do
      email = unique_user_email()

      conn =
        post(conn, "/users/register", %{
          "user" => valid_user_attributes(email: email)
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == "/"
    end

    test "render errors for invalid data", %{conn: conn} do
      conn =
        post(conn, "/users/register", %{
          "user" => %{"email" => "with spaces"}
        })

      response = html_response(conn, 200)
      assert response =~ "アカウント登録"
      assert response =~ "must have the @ sign and no spaces"
    end
  end
end
