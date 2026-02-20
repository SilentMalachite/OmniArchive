defmodule AlchemIiifWeb.InspectorLive.UploadTest do
  @moduledoc """
  Upload LiveView のセキュリティテスト。

  ウィザード Step 1（PDFアップロード画面）における
  ユーザー間データ分離を検証します。
  LiveView ソケットはプロセス単位で独立しているため、
  User A のアップロードエントリが User B に漏洩しないことを保証します。
  """
  use AlchemIiifWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import AlchemIiif.AccountsFixtures

  describe "security: uploads are isolated between users" do
    test "User A のアップロードファイルが User B に見えないこと" do
      # ── 1. セットアップ: 2人のユーザーを作成 ──
      user_a = user_fixture()
      user_b = user_fixture()

      # ── 2. User A: ログイン → LiveView マウント → ファイル選択 ──
      conn_a =
        build_conn()
        |> log_in_user(user_a)

      {:ok, view_a, _html} = live(conn_a, ~p"/lab")

      # PDF ファイルを選択（file_input でエントリを登録）
      pdf_input =
        file_input(view_a, "#upload-form", :pdf, [
          %{
            name: "secret_plan.pdf",
            content: <<0, 1, 2, 3, 4>>,
            type: "application/pdf"
          }
        ])

      # アップロードチャンクを送信してバリデーションを発火
      render_upload(pdf_input, "secret_plan.pdf")

      # User A のビューにファイル名が表示されることを確認
      html_a = render(view_a)
      assert html_a =~ "secret_plan.pdf"

      # ── 3. User B: ログイン → LiveView マウント → 分離を検証 ──
      conn_b =
        build_conn()
        |> log_in_user(user_b)

      {:ok, view_b, _html} = live(conn_b, ~p"/lab")

      # User B のビューに User A のファイル名が表示されないことを確認
      html_b = render(view_b)
      refute html_b =~ "secret_plan.pdf",
        "セキュリティ違反: User A のアップロード (secret_plan.pdf) が User B のセッションに漏洩しています"
    end
  end
end
