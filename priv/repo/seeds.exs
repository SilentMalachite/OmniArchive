# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     OmniArchive.Repo.insert!(%OmniArchive.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# --- 開発環境用: アップロードディレクトリのクリーンアップ ---
# DBリセット時に古いアップロードファイルが残る「ゴーストデータ」問題を防止
if Mix.env() == :dev do
  upload_path = Path.join([:code.priv_dir(:omni_archive), "static", "uploads"])

  if File.exists?(upload_path) do
    IO.puts("🧹 Cleaning up upload directory: #{upload_path}")
    File.rm_rf!(upload_path)
    File.mkdir_p!(upload_path)
  else
    IO.puts("📂 Creating upload directory: #{upload_path}")
    File.mkdir_p!(upload_path)
  end
end

# --- シードデータの投入 ---

# 1. デフォルト管理者ユーザーの作成
admin_email = "admin@example.com"
admin_password = "Password1234!"

case OmniArchive.Repo.get_by(OmniArchive.Accounts.User, email: admin_email) do
  nil ->
    {:ok, admin} =
      OmniArchive.Accounts.register_user(%{
        email: admin_email,
        password: admin_password
      })

    # adminロール付与 + メール確認済みに設定（開発用）
    admin
    |> Ecto.Changeset.change(%{role: "admin", confirmed_at: DateTime.utc_now(:second)})
    |> OmniArchive.Repo.update!()

    IO.puts("🔑 管理者ユーザーを作成しました: #{admin_email} (role: admin)")

  _existing ->
    IO.puts("👤 管理者ユーザーは既に存在します: #{admin_email}")
end

# 2. QAテスト用の一般ユーザーの作成
user_email = "user@example.com"
user_password = "Password1234!"

case OmniArchive.Repo.get_by(OmniArchive.Accounts.User, email: user_email) do
  nil ->
    {:ok, user} =
      OmniArchive.Accounts.register_user(%{
        email: user_email,
        password: user_password
      })

    # メール確認済みに設定（開発用）
    user
    |> Ecto.Changeset.change(%{confirmed_at: DateTime.utc_now(:second)})
    |> OmniArchive.Repo.update!()

    IO.puts("👤 一般ユーザーを作成しました: #{user_email} (role: user)")

  _existing ->
    IO.puts("👤 一般ユーザーは既に存在します: #{user_email}")
end
