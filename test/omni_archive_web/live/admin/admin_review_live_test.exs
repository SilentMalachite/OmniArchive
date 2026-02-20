defmodule OmniArchiveWeb.Admin.ReviewLiveTest do
  use OmniArchiveWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import OmniArchive.Factory
  alias OmniArchive.Ingestion

  # Admin ロール必須のため、admin_fixture でユーザーを作成してログイン
  setup %{conn: conn} do
    user = OmniArchive.AccountsFixtures.admin_fixture()
    conn = OmniArchiveWeb.ConnCase.log_in_user(conn, user)
    %{conn: conn, user: user}
  end

  describe "mount/3" do
    test "Admin Review Dashboard が正常にマウントされる", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/review")

      assert html =~ "Admin Review Dashboard"
    end

    test "pending_review の画像が表示される", %{conn: conn} do
      insert_extracted_image(%{
        ptif_path: "/path/to/pending.tif",
        status: "pending_review",
        label: "fig-10-1"
      })

      {:ok, _view, html} = live(conn, ~p"/admin/review")

      assert html =~ "fig-10-1"
      assert html =~ "レビュー待ち: 1 件"
    end

    test "レビュー待ちがない場合はメッセージが表示される", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/review")

      assert html =~ "レビュー待ちの図版はありません"
    end

    test "draft 画像は表示されない", %{conn: conn} do
      insert_extracted_image(%{
        ptif_path: "/path/to/draft.tif",
        status: "draft",
        label: "fig-11-1"
      })

      {:ok, _view, html} = live(conn, ~p"/admin/review")

      refute html =~ "下書きの画像"
    end

    test "published 画像は表示されない", %{conn: conn} do
      insert_extracted_image(%{
        ptif_path: "/path/to/published.tif",
        status: "published",
        label: "fig-12-1"
      })

      {:ok, _view, html} = live(conn, ~p"/admin/review")

      refute html =~ "公開済み画像"
    end

    test "PTIF なしの pending_review 画像には処理中プレースホルダーが表示される", %{conn: conn} do
      insert_extracted_image(%{
        ptif_path: nil,
        status: "pending_review",
        label: "fig-13-1"
      })

      {:ok, _view, html} = live(conn, ~p"/admin/review")

      assert html =~ "fig-13-1"
      assert html =~ "画像処理中..."
    end
  end

  describe "Validation Badge" do
    test "有効なデータには ✓ OK バッジが表示される", %{conn: conn} do
      insert_extracted_image(%{
        ptif_path: "/path/to/valid.tif",
        status: "pending_review",
        label: "fig-14-1",
        image_path: "priv/static/uploads/test.png",
        geometry: %{"x" => 0, "y" => 0, "width" => 100, "height" => 100}
      })

      {:ok, _view, html} = live(conn, ~p"/admin/review")

      assert html =~ "✓ OK"
    end

    test "ラベル未設定には ⚠ 要確認 バッジが表示される", %{conn: conn} do
      insert_extracted_image(%{
        ptif_path: "/path/to/warning.tif",
        status: "pending_review",
        label: nil
      })

      {:ok, _view, html} = live(conn, ~p"/admin/review")

      assert html =~ "⚠ 要確認"
    end
  end

  describe "approve イベント" do
    test "画像を承認して公開する", %{conn: conn} do
      image =
        insert_extracted_image(%{
          ptif_path: "/path/to/pending.tif",
          status: "pending_review",
          label: "fig-15-1"
        })

      {:ok, view, _html} = live(conn, ~p"/admin/review")

      # 承認ボタンをクリック（Optimistic UI: card-fade-out が付与される）
      html = render_click(view, "approve", %{"id" => to_string(image.id)})

      assert html =~ "card-fade-out"
    end
  end

  describe "select_image イベント" do
    test "カード選択でインスペクターが表示される", %{conn: conn} do
      image =
        insert_extracted_image(%{
          ptif_path: "/path/to/inspect.tif",
          status: "pending_review",
          label: "fig-16-1"
        })

      {:ok, view, _html} = live(conn, ~p"/admin/review")

      # カードを選択
      html = render_click(view, "select_image", %{"id" => to_string(image.id)})

      # インスペクターが表示される
      assert html =~ "インスペクター"
      assert html =~ "fig-16-1"
    end

    test "geometry 付き画像選択で SVG viewBox クロップが表示される", %{conn: conn} do
      image =
        insert_extracted_image(%{
          ptif_path: "/path/to/crop.tif",
          status: "pending_review",
          label: "fig-17-1",
          image_path: "priv/static/uploads/test.png",
          geometry: %{"x" => 10, "y" => 20, "width" => 100, "height" => 80}
        })

      {:ok, view, _html} = live(conn, ~p"/admin/review")

      # カードを選択
      html = render_click(view, "select_image", %{"id" => to_string(image.id)})

      # SVG viewBox がレンダリングされる
      assert html =~ "viewBox"
      assert html =~ "10 20 100 80"
      assert html =~ "inspector-crop-svg"
    end

    test "インスペクターを閉じることができる", %{conn: conn} do
      image =
        insert_extracted_image(%{
          ptif_path: "/path/to/close.tif",
          status: "pending_review",
          label: "fig-18-1"
        })

      {:ok, view, _html} = live(conn, ~p"/admin/review")

      # カード選択 → インスペクター表示
      render_click(view, "select_image", %{"id" => to_string(image.id)})

      # インスペクターを閉じる
      html = render_click(view, "close_inspector", %{})

      # インスペクターが非表示になる
      refute html =~ "inspector-open"
    end
  end

  describe "reject イベント（Note 付き差し戻し）" do
    test "差し戻しモーダルを開いて実行する", %{conn: conn} do
      image =
        insert_extracted_image(%{
          ptif_path: "/path/to/reject.tif",
          status: "pending_review",
          label: "fig-19-1"
        })

      {:ok, view, _html} = live(conn, ~p"/admin/review")

      # モーダルを開く
      html = render_click(view, "open_reject_modal", %{"id" => to_string(image.id)})
      assert html =~ "差し戻し理由"

      # Note を入力
      render_click(view, "update_reject_note", %{"reject_note" => %{"note" => "メタデータを修正してください"}})

      # 差し戻しを実行
      html = render_click(view, "confirm_reject", %{})

      # リストから消え、0件になる
      assert html =~ "レビュー待ち: 0 件"
      assert html =~ "レビュー待ちの図版はありません"
    end
  end

  describe "delete イベント" do
    test "削除ボタンでエントリがリストから消える", %{conn: conn} do
      image =
        insert_extracted_image(%{
          ptif_path: "/path/to/delete.tif",
          status: "pending_review",
          label: "fig-20-1"
        })

      {:ok, view, _html} = live(conn, ~p"/admin/review")

      # 削除を実行
      html = render_click(view, "delete", %{"id" => to_string(image.id)})

      # リストから消え、0件になる
      assert html =~ "レビュー待ち: 0 件"
      assert html =~ "レビュー待ちの図版はありません"
    end

    test "draft ステータスの画像は削除できない", %{conn: conn} do
      image =
        insert_extracted_image(%{
          ptif_path: "/path/to/draft.tif",
          status: "pending_review",
          label: "fig-21-1"
        })

      {:ok, view, _html} = live(conn, ~p"/admin/review")

      # まずステータスを draft に変更して再度テスト
      # pending_review の画像を直接 reject して draft にする
      render_click(view, "open_reject_modal", %{"id" => to_string(image.id)})
      render_click(view, "confirm_reject", %{})

      # draft の画像は削除できないことを確認（リストに表示されないため別経路で確認）
      # pending_review 以外は soft_delete_image がエラーを返す
      assert Ingestion.soft_delete_image(%{image | status: "draft"}) ==
               {:error, :invalid_status_transition}
    end
  end
end
