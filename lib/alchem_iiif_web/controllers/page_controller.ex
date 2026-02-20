defmodule AlchemIiifWeb.PageController do
  use AlchemIiifWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  # /admin へのアクセスを /admin/review にリダイレクト
  def redirect_admin(conn, _params) do
    redirect(conn, to: ~p"/admin/review")
  end
end
