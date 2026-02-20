defmodule Mix.Tasks.Review.CheckDbVersion do
  @moduledoc """
  PostgreSQL バージョンチェック Mix タスク。

  `mix review` パイプラインの最初のステップとして実行し、
  ローカルの PostgreSQL が 15.0 以上であることを検証します。

  ## なぜ PostgreSQL 15+ が必要か

  - 考古学メタデータの JSONB 最適化（VCI 122）
  - MERGE ステートメントのサポート
  - 高度な JSON パス式の改善

  ## 使用方法

      mix review.check_db_version

  読み取り専用のバリデーションであり、データベースの変更は一切行いません。
  """
  @shortdoc "PostgreSQL バージョンが 15.0 以上か検証"

  use Mix.Task

  # PostgreSQL 15.0 に相当するバージョン番号
  @min_version_num 150_000

  @impl Mix.Task
  def run(_args) do
    # Ecto / Postgrex の依存を起動
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:postgrex)

    repo_config = Application.get_env(:alchem_iiif, AlchemIiif.Repo)

    # Postgrex で直接接続（Repo を起動せずに読み取り専用クエリを実行）
    conn_opts = [
      hostname: repo_config[:hostname] || "localhost",
      username: repo_config[:username],
      password: repo_config[:password] || "",
      database: repo_config[:database]
    ]

    case Postgrex.start_link(conn_opts) do
      {:ok, conn} ->
        check_version(conn)

      {:error, reason} ->
        print_connection_error(reason)
        System.halt(1)
    end
  end

  defp check_version(conn) do
    case Postgrex.query(conn, "SELECT current_setting('server_version_num')::integer", []) do
      {:ok, %{rows: [[version_num]]}} ->
        version_string = format_version(version_num)

        if version_num >= @min_version_num do
          IO.puts("""

          \e[32m  ✅ PostgreSQL version check: PASS (detected: #{version_string})\e[0m
          """)
        else
          print_version_error(version_string)
          System.halt(1)
        end

      {:error, reason} ->
        IO.puts("""

        \e[31m═══════════════════════════════════════════════════\e[0m
        \e[31m  ❌ ERROR: バージョンクエリの実行に失敗しました\e[0m
        \e[31m  理由: #{inspect(reason)}\e[0m
        \e[31m═══════════════════════════════════════════════════\e[0m
        """)

        System.halt(1)
    end
  end

  defp print_version_error(version_string) do
    IO.puts("""

    \e[41m\e[37m═══════════════════════════════════════════════════\e[0m
    \e[41m\e[37m  ❌ ERROR: PostgreSQL 15.0 or higher is required.\e[0m
    \e[41m\e[37m  Current version: #{version_string}\e[0m
    \e[41m\e[37m═══════════════════════════════════════════════════\e[0m
    \e[33m  JSONB 最適化 (VCI 122) および MERGE 文のサポートには\e[0m
    \e[33m  PostgreSQL 15.0 以上が必要です。\e[0m
    """)
  end

  defp print_connection_error(reason) do
    IO.puts("""

    \e[31m═══════════════════════════════════════════════════\e[0m
    \e[31m  ❌ ERROR: データベースに接続できません\e[0m
    \e[31m  理由: #{inspect(reason)}\e[0m
    \e[31m═══════════════════════════════════════════════════\e[0m
    """)
  end

  @doc """
  バージョン番号整数を "X.Y" 形式の文字列に変換します。

  ## 例

      iex> Mix.Tasks.Review.CheckDbVersion.format_version(150004)
      "15.4"

      iex> Mix.Tasks.Review.CheckDbVersion.format_version(140012)
      "14.12"
  """
  def format_version(version_num) do
    major = div(version_num, 10_000)
    minor = rem(version_num, 10_000) |> div(100)
    "#{major}.#{minor}"
  end
end
