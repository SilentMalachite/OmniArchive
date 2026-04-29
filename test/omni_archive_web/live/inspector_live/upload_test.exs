defmodule OmniArchiveWeb.InspectorLive.UploadTest do
  @moduledoc """
  Upload LiveView のセキュリティテスト。

  ウィザード Step 1（PDFアップロード画面）における
  ユーザー間データ分離を検証します。
  LiveView ソケットはプロセス単位で独立しているため、
  User A のアップロードエントリが User B に漏洩しないことを保証します。
  """
  use OmniArchiveWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import OmniArchive.AccountsFixtures
  import OmniArchive.Factory

  describe "security: uploads are isolated between users" do
    test "User A のアップロードファイルが User B に見えないこと" do
      # ── 1. セットアップ: 2人のユーザーを作成 ──
      user_a = user_fixture()
      user_b = user_fixture()

      # ── 2. User A: ログイン → LiveView マウント → ファイル選択 ──
      conn_a =
        build_conn()
        |> log_in_user(user_a)

      {:ok, view_a, _html} = live(conn_a, ~p"/lab/upload")

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

  describe "security: upload quotas" do
    test "処理中の PDF があるユーザーは追加アップロードを開始できない" do
      user = user_fixture()
      insert_pdf_source(%{user_id: user.id, status: "converting"})

      conn =
        build_conn()
        |> log_in_user(user)

      {:ok, view, _html} = live(conn, ~p"/lab/upload")

      html =
        view
        |> form("#upload-form", %{"color_mode" => "mono"})
        |> render_submit()

      assert html =~ "処理中のPDFがあります"
    end

    test "24時間のアップロード上限を超えたユーザーは追加アップロードを開始できない" do
      user = user_fixture()

      for _ <- 1..20 do
        insert_pdf_source(%{user_id: user.id, status: "ready"})
      end

      conn =
        build_conn()
        |> log_in_user(user)

      {:ok, view, _html} = live(conn, ~p"/lab/upload")

      html =
        view
        |> form("#upload-form", %{"color_mode" => "mono"})
        |> render_submit()

      assert html =~ "1日のアップロード上限"
    end
  end

  describe "security: event parameter validation" do
    test "不正なタブ名を送っても LiveView がクラッシュしない" do
      user = user_fixture()

      conn =
        build_conn()
        |> log_in_user(user)

      {:ok, view, _html} = live(conn, ~p"/lab/upload")

      html = render_click(view, "switch_tab", %{"tab" => "not_a_tab"})

      assert html =~ "PDFファイルをアップロード"
    end
  end

  describe "PDF page estimate" do
    test "PDF読み込みページ数の目安を入力できる" do
      user = user_fixture()

      conn =
        build_conn()
        |> log_in_user(user)

      {:ok, view, _html} = live(conn, ~p"/lab/upload")

      html = render(view)

      assert html =~ "PDFページ数の目安"
      assert html =~ ~s(id="estimated-page-count")
      assert html =~ ~s(name="estimated_page_count")
      assert html =~ ~s(value="200")

      html =
        view
        |> form("#upload-form", %{"color_mode" => "mono", "estimated_page_count" => "120"})
        |> render_change()

      assert html =~ ~s(value="120")
    end
  end
end
