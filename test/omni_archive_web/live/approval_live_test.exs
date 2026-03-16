defmodule OmniArchiveWeb.ApprovalLiveTest do
  use OmniArchiveWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import OmniArchive.Factory
  alias OmniArchive.Repo

  setup :register_and_log_in_user

  describe "mount/3" do
    test "承認ダッシュボードが正常にマウントされる", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/lab/approval")

      assert html =~ "承認ダッシュボード"
    end

    test "レビュー待ちの画像が表示される", %{conn: conn} do
      insert_extracted_image(%{
        ptif_path: "/path/to/pending.tif",
        status: "pending_review",
        label: "fig-30-1"
      })

      {:ok, _view, html} = live(conn, ~p"/lab/approval")

      assert html =~ "fig-30-1"
      assert html =~ "レビュー待ち: 1 件"
    end

    test "レビュー待ちがない場合はメッセージが表示される", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/lab/approval")

      assert html =~ "レビュー待ちの図版はありません"
    end

    test "draft 画像は承認ダッシュボードに表示されない", %{conn: conn} do
      insert_extracted_image(%{
        ptif_path: "/path/to/draft.tif",
        status: "draft",
        label: "fig-31-1"
      })

      {:ok, _view, html} = live(conn, ~p"/lab/approval")

      refute html =~ "下書きの画像"
    end

    test "metadata の値を優先して profile metadata field を表示する", %{conn: conn} do
      image =
        insert_extracted_image(%{
          ptif_path: "/path/to/pending.tif",
          status: "pending_review",
          site: "旧承認市遺跡",
          period: "旧承認時代",
          artifact_type: "旧承認種別"
        })

      Repo.query!(
        """
        UPDATE extracted_images
        SET metadata = jsonb_build_object('site', $1::text, 'period', $2::text, 'artifact_type', $3::text)
        WHERE id = $4
        """,
        ["新承認市遺跡", "新承認時代", "新承認種別", image.id]
      )

      {:ok, _view, html} = live(conn, ~p"/lab/approval")

      assert html =~ "新承認市遺跡"
      assert html =~ "新承認時代"
      assert html =~ "新承認種別"
      refute html =~ "旧承認市遺跡"
    end
  end

  describe "approve イベント" do
    test "画像を承認して公開する", %{conn: conn} do
      image =
        insert_extracted_image(%{
          ptif_path: "/path/to/pending.tif",
          status: "pending_review",
          label: "fig-32-1"
        })

      {:ok, view, _html} = live(conn, ~p"/lab/approval")

      html = render_click(view, "approve", %{"id" => to_string(image.id)})

      # 承認後、レビュー待ちリストから消え、0件になる
      assert html =~ "レビュー待ち: 0 件"
      assert html =~ "レビュー待ちの図版はありません"
    end
  end

  describe "reject イベント" do
    test "画像を差し戻す", %{conn: conn} do
      image =
        insert_extracted_image(%{
          ptif_path: "/path/to/pending.tif",
          status: "pending_review",
          label: "fig-33-1"
        })

      {:ok, view, _html} = live(conn, ~p"/lab/approval")

      html = render_click(view, "reject", %{"id" => to_string(image.id)})

      # 差し戻し後、レビュー待ちリストから消え、0件になる
      assert html =~ "レビュー待ち: 0 件"
      assert html =~ "レビュー待ちの図版はありません"
    end
  end
end
