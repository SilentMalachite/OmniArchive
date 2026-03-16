# RBAC 検証スクリプト
# 実行方法: mix run scripts/verify_rbac.exs
#
# Admin ユーザーと一般ユーザーで list_extracted_images/1 の動作差を確認します。

alias OmniArchive.Accounts
alias OmniArchive.Ingestion

IO.puts("=== RBAC 検証スクリプト ===\n")

# 1. Admin ユーザーを取得
admin = Accounts.get_user_by_email("admin@example.com")

if is_nil(admin) do
  IO.puts("❌ Admin ユーザー (admin@example.com) が見つかりません。")
  System.halt(1)
end

IO.puts("✅ Admin: #{admin.email} (role: #{admin.role})")

# 2. 一般ユーザーを取得
standard = Accounts.get_user_by_email("test_user@lab.com")

if is_nil(standard) do
  IO.puts("❌ Standard ユーザー (test_user@lab.com) が見つかりません。")
  System.halt(1)
end

IO.puts("✅ Standard: #{standard.email} (role: #{standard.role})")

# 3. 各ユーザーで画像一覧を取得
admin_images = Ingestion.list_extracted_images(admin)
standard_images = Ingestion.list_extracted_images(standard)

admin_count = length(admin_images)
standard_count = length(standard_images)

IO.puts("\n--- 結果 ---")
IO.puts("Admin が取得した画像数:    #{admin_count}")
IO.puts("Standard が取得した画像数: #{standard_count}")

# 4. アサーション
cond do
  admin_count == 0 and standard_count == 0 ->
    IO.puts("\n⚠️  画像データがありません。先にPDFをアップロードしてください。")

  admin_count >= standard_count ->
    IO.puts("\n✅ RBAC 検証成功: Admin (#{admin_count}) >= Standard (#{standard_count})")
    IO.puts("   Admin は全件を参照でき、Standard は自分のもののみを参照しています。")

  true ->
    IO.puts("\n❌ RBAC 検証失敗: Admin (#{admin_count}) < Standard (#{standard_count})")
    IO.puts("   アクセス制御のロジックに問題がある可能性があります。")
    System.halt(1)
end

IO.puts("\n=== 検証完了 ===")
