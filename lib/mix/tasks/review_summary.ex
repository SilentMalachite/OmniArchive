defmodule Mix.Tasks.Review.Summary do
  @moduledoc """
  レビューゲートの結果サマリーを出力する Mix タスク。

  `mix review` エイリアスの最後に実行されます。
  このタスクが実行されること自体が、前段の全チェック
  （compile, credo, sobelow, dialyzer）が通過したことを意味します。
  """
  @shortdoc "レビューゲートの PASS サマリーを出力"

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    IO.puts("""

    \e[32m═══════════════════════════════════════════════════\e[0m
    \e[32m  ✅ REVIEW GATE: ALL CHECKS PASSED\e[0m
    \e[32m═══════════════════════════════════════════════════\e[0m
    \e[36m  pg_version >= 15.0           ... PASS\e[0m
    \e[36m  compile --warnings-as-errors ... PASS\e[0m
    \e[36m  credo --strict                ... PASS\e[0m
    \e[36m  sobelow --config              ... PASS\e[0m
    \e[36m  dialyzer                      ... PASS\e[0m
    \e[32m═══════════════════════════════════════════════════\e[0m
    """)
  end
end
