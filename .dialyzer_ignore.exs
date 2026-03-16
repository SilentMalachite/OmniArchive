[
  # Dialyzer 既知の警告を無視
  # Mix.Task behaviour は Elixir 1.19 の Dialyzer PLT に含まれない既知の問題
  ~r/callback_info_missing/,
  # Mix.Task.run/1 は Mix 環境限定の関数であり PLT に含まれない
  ~r/unknown_function.*Mix\.Task\.run/
]
