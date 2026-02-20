# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     AlchemIiif.Repo.insert!(%AlchemIiif.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# --- 開発環境用: アップロードディレクトリのクリーンアップ ---
# DBリセット時に古いアップロードファイルが残る「ゴーストデータ」問題を防止
if Mix.env() == :dev do
  upload_path = Path.join([:code.priv_dir(:alchem_iiif), "static", "uploads"])

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

# デフォルト管理者ユーザーの作成
admin_email = "admin@example.com"
admin_password = "password1234"

case AlchemIiif.Repo.get_by(AlchemIiif.Accounts.User, email: admin_email) do
  nil ->
    {:ok, admin} =
      AlchemIiif.Accounts.register_user(%{
        email: admin_email,
        password: admin_password
      })

    # メール確認済みに設定（開発用）
    admin
    |> Ecto.Changeset.change(%{confirmed_at: DateTime.utc_now(:second)})
    |> AlchemIiif.Repo.update!()

    IO.puts("👤 管理者ユーザーを作成しました: #{admin_email}")

  _existing ->
    IO.puts("👤 管理者ユーザーは既に存在します: #{admin_email}")
end
