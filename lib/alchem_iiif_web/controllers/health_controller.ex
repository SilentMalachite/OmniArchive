defmodule AlchemIiifWeb.HealthController do
  @moduledoc """
  ヘルスチェック用コントローラー。
  コンテナオーケストレーター (Docker, K8s) からのヘルスチェックに応答します。
  """
  use AlchemIiifWeb, :controller

  def show(conn, _params) do
    json(conn, %{status: "ok", app: "alchem_iiif"})
  end
end
