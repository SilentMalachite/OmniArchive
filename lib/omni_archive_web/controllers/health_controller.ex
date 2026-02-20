defmodule OmniArchiveWeb.HealthController do
  @moduledoc """
  ヘルスチェック用コントローラー。
  コンテナオーケストレーター (Docker, K8s) からのヘルスチェックに応答します。
  """
  use OmniArchiveWeb, :controller

  def show(conn, _params) do
    json(conn, %{status: "ok", app: "omni_archive"})
  end
end
