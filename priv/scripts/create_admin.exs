# priv/scripts/create_admin.exs
# ─────────────────────────────────────────────────
# 初回管理者ユーザーを作成する IEx スクリプト
#
# 使用方法:
#   mix run priv/scripts/create_admin.exs
#
# または IEx 内で実行:
#   iex -S mix
#   c "priv/scripts/create_admin.exs"
#
# 環境変数で指定する場合:
#   ADMIN_EMAIL=admin@example.com ADMIN_PASSWORD=your_password_here mix run priv/scripts/create_admin.exs
# ─────────────────────────────────────────────────

alias OmniArchive.Repo
alias OmniArchive.Accounts.User

# 環境変数またはデフォルト値からパラメータを取得
email    = System.get_env("ADMIN_EMAIL")    || "admin@example.com"
password = System.get_env("ADMIN_PASSWORD") || "Admin12345678"

IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
IO.puts("  管理者ユーザー作成スクリプト")
IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
IO.puts("  Email:    #{email}")
IO.puts("  Role:     admin")
IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

# ユーザーの登録（email + password の changeset を使用）
result =
  %User{}
  |> User.email_changeset(%{email: email})
  |> User.password_changeset(%{password: password})
  |> Ecto.Changeset.put_change(:role, "admin")
  |> Repo.insert()

case result do
  {:ok, user} ->
    IO.puts("\n✅ 管理者ユーザーを作成しました！")
    IO.puts("   ID:    #{user.id}")
    IO.puts("   Email: #{user.email}")
    IO.puts("   Role:  #{user.role}")
    IO.puts("\n⚠️  パスワードを安全に保管してください。")

  {:error, changeset} ->
    IO.puts("\n❌ 作成に失敗しました:")

    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.each(fn {field, errors} ->
      IO.puts("   #{field}: #{Enum.join(errors, ", ")}")
    end)
end
