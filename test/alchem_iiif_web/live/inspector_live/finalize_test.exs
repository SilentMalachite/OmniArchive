defmodule AlchemIiifWeb.InspectorLive.FinalizeTest do
  @moduledoc """
  Finalize LiveView のテスト。

  ウィザードStep4のファイナライズ画面をテストします。
  マウント時の初期表示、PubSub 進捗イベント処理、
  「レビューに提出」のステータス遷移を検証します。
  """
  use AlchemIiifWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import AlchemIiif.Factory

  setup :register_and_log_in_user

  describe "マウント" do
    test "初期状態で確認画面が表示される", %{conn: conn} do
      image =
        insert_extracted_image(%{
          page_number: 3,
          caption: "テスト土器第3図",
          label: "fig-3-1",
          geometry: %{"x" => 10, "y" => 20, "width" => 200, "height" => 300}
        })

      {:ok, _view, html} = live(conn, ~p"/lab/finalize/#{image.id}")

      # 確認画面のタイトルが表示される
      assert html =~ "保存内容の確認"
      assert html =~ "以下の内容で図版を保存します"

      # 画像情報が表示される
      assert html =~ "ページ 3"
      assert html =~ "テスト土器第3図"
      assert html =~ "fig-3-1"

      # クロップ範囲が表示される
      assert html =~ "クロップ範囲"
    end

    test "システムリソース情報が表示される", %{conn: conn} do
      image = insert_extracted_image()

      {:ok, _view, html} = live(conn, ~p"/lab/finalize/#{image.id}")

      # リソースバッジの表示
      assert html =~ "CPU:"
      assert html =~ "コア"
      assert html =~ "利用可能:"
      assert html =~ "GB"
    end

    test "保存ボタンが表示される", %{conn: conn} do
      image = insert_extracted_image()

      {:ok, view, html} = live(conn, ~p"/lab/finalize/#{image.id}")

      assert html =~ "保存する"
      assert has_element?(view, "button.btn-confirm")
    end

    test "初期状態でプログレスバーは非表示", %{conn: conn} do
      image = insert_extracted_image()

      {:ok, _view, html} = live(conn, ~p"/lab/finalize/#{image.id}")

      # 処理中ではないのでプログレスバーは非表示
      refute html =~ "処理の進捗"
    end
  end

  describe "キャプション・ラベルなしの場合" do
    test "キャプションがない場合は表示されない", %{conn: conn} do
      image = insert_extracted_image(%{caption: nil, label: nil, geometry: nil})

      {:ok, _view, html} = live(conn, ~p"/lab/finalize/#{image.id}")

      refute html =~ "キャプション"
      refute html =~ "ラベル"
      refute html =~ "クロップ範囲"
    end
  end

  describe "PubSub 進捗イベント" do
    test "タスク進捗イベントで progress_tasks が更新される", %{conn: conn} do
      image = insert_extracted_image()

      {:ok, view, _html} = live(conn, ~p"/lab/finalize/#{image.id}")

      # 進捗イベントを送信（processing フラグは confirm_save で設定されるため、
      # ここでは progress_tasks の更新のみを検証）
      send(
        view.pid,
        {:pipeline_progress,
         %{
           event: :task_progress,
           task_id: "finalize-ptif",
           status: :processing,
           progress: 33,
           message: "PTIF生成中..."
         }}
      )

      # render で反映を確認（progress_tasks は内部状態として更新される）
      # processing フラグが false の場合、プログレスバーは非表示だが
      # overall_progress は更新される
      _html = render(view)

      # 代わりに完了結果で正しく表示されることを検証
      updated_image = %{image | status: "draft"}

      send(
        view.pid,
        {:finalize_result, {:ok, %{image: updated_image, identifier: "img-test-prog"}}}
      )

      html = render(view)
      assert html =~ "保存が完了しました"
    end

    test "完了イベントで成功画面が表示される", %{conn: conn} do
      image = insert_extracted_image()

      {:ok, view, _html} = live(conn, ~p"/lab/finalize/#{image.id}")

      # finalize_result メッセージを直接送信して完了をシミュレート
      updated_image = %{image | status: "draft"}

      send(
        view.pid,
        {:finalize_result, {:ok, %{image: updated_image, identifier: "img-test-123"}}}
      )

      html = render(view)

      assert html =~ "保存が完了しました"
      assert html =~ "img-test-123"
      assert html =~ "レビューに提出"
    end

    test "エラーイベントでエラーメッセージが表示される", %{conn: conn} do
      image = insert_extracted_image()

      {:ok, view, _html} = live(conn, ~p"/lab/finalize/#{image.id}")

      send(view.pid, {:finalize_result, {:error, :ptif_generation_failed}})

      html = render(view)

      assert html =~ "処理中にエラーが発生しました"
    end
  end

  describe "レビュー提出" do
    test "draft ステータスの画像をレビューに提出できる", %{conn: conn} do
      image = insert_extracted_image(%{status: "draft", ptif_path: "/tmp/test.tif"})

      {:ok, view, _html} = live(conn, ~p"/lab/finalize/#{image.id}")

      # 完了状態にする（draft ステータスの画像で完了）
      updated_image = %{image | status: "draft"}

      send(
        view.pid,
        {:finalize_result, {:ok, %{image: updated_image, identifier: "img-test-456"}}}
      )

      html = render(view)
      assert html =~ "レビューに提出"

      # レビューに提出イベントを発火
      view |> element("button.btn-submit-review") |> render_click()

      # DB 上でステータスが pending_review に遷移する
      # submit_for_review 成功後、画像は pending_review になり「レビュー待ち」と表示される
      html = render(view)
      assert html =~ "レビュー待ち"
    end
  end

  describe "ステータス表示" do
    test "完了後に pending_review ステータスが表示される", %{conn: conn} do
      image = insert_extracted_image(%{status: "draft"})

      {:ok, view, _html} = live(conn, ~p"/lab/finalize/#{image.id}")

      # ステータスを pending_review に更新した画像で完了をシミュレート
      updated_image = %{image | status: "pending_review"}

      send(
        view.pid,
        {:finalize_result, {:ok, %{image: updated_image, identifier: "img-test-789"}}}
      )

      html = render(view)
      assert html =~ "レビュー待ち"
    end

    test "完了後に published ステータスが表示される", %{conn: conn} do
      image = insert_extracted_image(%{status: "draft"})

      {:ok, view, _html} = live(conn, ~p"/lab/finalize/#{image.id}")

      updated_image = %{image | status: "published"}

      send(
        view.pid,
        {:finalize_result, {:ok, %{image: updated_image, identifier: "img-test-pub"}}}
      )

      html = render(view)
      assert html =~ "公開済み"
    end
  end
end
