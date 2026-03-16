defmodule OmniArchiveWeb.PipelineLiveTest do
  @moduledoc """
  PipelineLive の LiveView テスト。

  PubSub イベント受信時の UI 更新、システムリソース情報表示、
  進捗バーの表示、完了・エラー状態の UI を検証します。
  """
  use OmniArchiveWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias OmniArchive.Pipeline

  @pubsub OmniArchive.PubSub

  setup :register_and_log_in_user

  describe "マウント" do
    test "初期状態でリソース情報が表示される", %{conn: conn} do
      pipeline_id = Pipeline.generate_pipeline_id()
      {:ok, view, html} = live(conn, ~p"/lab/pipeline/#{pipeline_id}")

      # システムリソース情報セクションが表示される
      assert html =~ "システムリソース"
      assert html =~ "CPU コア数"
      assert html =~ "総メモリ"
      assert html =~ "利用可能メモリ"
      assert html =~ "パイプライン並列度"
      assert html =~ "最大PTIF同時変換"

      # 処理中インジケータが表示される
      assert html =~ "処理中です"

      # 全体進捗バーが0%で表示される
      assert html =~ "0%"
      assert has_element?(view, "[role=\"progressbar\"]")
    end

    test "初期状態ではタスク一覧が非表示", %{conn: conn} do
      pipeline_id = Pipeline.generate_pipeline_id()
      {:ok, view, _html} = live(conn, ~p"/lab/pipeline/#{pipeline_id}")

      # tasks-title クラスの要素が存在しないことを確認
      # （CSSコメントに「タスク一覧」文字列が含まれるため、テキストマッチではなくDOM要素で判定）
      refute has_element?(view, ".tasks-title")
    end
  end

  describe "PubSub イベント処理" do
    test "pipeline_started イベントでフェーズメッセージが更新される", %{conn: conn} do
      pipeline_id = Pipeline.generate_pipeline_id()
      {:ok, view, _html} = live(conn, ~p"/lab/pipeline/#{pipeline_id}")

      # PubSub でイベントを送信
      Phoenix.PubSub.broadcast(@pubsub, Pipeline.topic(pipeline_id), {
        :pipeline_progress,
        %{
          event: :pipeline_started,
          phase: :pdf_extraction,
          message: "PDF変換を開始します..."
        }
      })

      # UI が更新される
      html = render(view)
      assert html =~ "PDF変換を開始します..."
    end

    test "task_progress イベントでタスクカードが表示される", %{conn: conn} do
      pipeline_id = Pipeline.generate_pipeline_id()
      {:ok, view, _html} = live(conn, ~p"/lab/pipeline/#{pipeline_id}")

      # タスク進捗イベントを送信
      Phoenix.PubSub.broadcast(@pubsub, Pipeline.topic(pipeline_id), {
        :pipeline_progress,
        %{
          event: :task_progress,
          task_id: "page-1",
          status: :processing,
          progress: 25,
          message: "ページ 1 を処理中"
        }
      })

      html = render(view)
      assert html =~ "タスク一覧"
      assert html =~ "ページ 1 を処理中"
    end

    test "task_progress の completed ステータスで完了バッジが表示される", %{conn: conn} do
      pipeline_id = Pipeline.generate_pipeline_id()
      {:ok, view, _html} = live(conn, ~p"/lab/pipeline/#{pipeline_id}")

      Phoenix.PubSub.broadcast(@pubsub, Pipeline.topic(pipeline_id), {
        :pipeline_progress,
        %{
          event: :task_progress,
          task_id: "page-1",
          status: :completed,
          progress: 100,
          message: "ページ 1 を登録しました"
        }
      })

      html = render(view)
      assert html =~ "ページ 1 を登録しました"
      assert html =~ "完了"
    end

    test "複数タスクの進捗で全体進捗が計算される", %{conn: conn} do
      pipeline_id = Pipeline.generate_pipeline_id()
      {:ok, view, _html} = live(conn, ~p"/lab/pipeline/#{pipeline_id}")

      # タスク1: 完了
      Phoenix.PubSub.broadcast(@pubsub, Pipeline.topic(pipeline_id), {
        :pipeline_progress,
        %{
          event: :task_progress,
          task_id: "page-1",
          status: :completed,
          progress: 50,
          message: "ページ 1 完了"
        }
      })

      # タスク2: 処理中
      Phoenix.PubSub.broadcast(@pubsub, Pipeline.topic(pipeline_id), {
        :pipeline_progress,
        %{
          event: :task_progress,
          task_id: "page-2",
          status: :processing,
          progress: 50,
          message: "ページ 2 処理中"
        }
      })

      html = render(view)
      # 2タスク中1つ完了 → 全体進捗50%
      assert html =~ "50%"
    end

    test "pipeline_complete イベントで完了状態になる", %{conn: conn} do
      pipeline_id = Pipeline.generate_pipeline_id()
      {:ok, view, _html} = live(conn, ~p"/lab/pipeline/#{pipeline_id}")

      Phoenix.PubSub.broadcast(@pubsub, Pipeline.topic(pipeline_id), {
        :pipeline_progress,
        %{
          event: :pipeline_complete,
          phase: :pdf_extraction,
          total: 5,
          succeeded: 5,
          failed: 0
        }
      })

      html = render(view)
      assert html =~ "処理が完了しました"
      assert html =~ "100%"
      # 完了ボタンが表示される
      assert html =~ "完了 — 次へ進む"
      # 処理結果サマリーが表示される
      assert html =~ "処理結果"
    end

    test "pipeline_error イベントでエラーメッセージが表示される", %{conn: conn} do
      pipeline_id = Pipeline.generate_pipeline_id()
      {:ok, view, _html} = live(conn, ~p"/lab/pipeline/#{pipeline_id}")

      Phoenix.PubSub.broadcast(@pubsub, Pipeline.topic(pipeline_id), {
        :pipeline_progress,
        %{
          event: :pipeline_error,
          phase: :pdf_extraction,
          message: "PDF変換に失敗しました"
        }
      })

      html = render(view)
      assert html =~ "PDF変換に失敗しました"
      assert html =~ "エラーが発生しました"
    end
  end

  describe "ナビゲーション" do
    test "完了後に「次へ進む」ボタンで移動できる", %{conn: conn} do
      pipeline_id = Pipeline.generate_pipeline_id()
      {:ok, view, _html} = live(conn, ~p"/lab/pipeline/#{pipeline_id}")

      # 完了状態にする
      Phoenix.PubSub.broadcast(@pubsub, Pipeline.topic(pipeline_id), {
        :pipeline_progress,
        %{
          event: :pipeline_complete,
          phase: :pdf_extraction,
          total: 1,
          succeeded: 1,
          failed: 0
        }
      })

      # 「次へ進む」ボタンが存在する
      html = render(view)
      assert html =~ "完了 — 次へ進む"
    end

    test "pdf_source_id付き完了イベントでBrowseページへ遷移する", %{conn: conn} do
      # PDFソースを作成
      {:ok, pdf_source} =
        OmniArchive.Ingestion.create_pdf_source(%{
          filename: "test.pdf",
          status: "ready"
        })

      pipeline_id = Pipeline.generate_pipeline_id()
      {:ok, view, _html} = live(conn, ~p"/lab/pipeline/#{pipeline_id}")

      # pdf_source_id を含む完了イベントを送信
      Phoenix.PubSub.broadcast(@pubsub, Pipeline.topic(pipeline_id), {
        :pipeline_progress,
        %{
          event: :pipeline_complete,
          phase: :pdf_extraction,
          total: 1,
          succeeded: 1,
          failed: 0,
          pdf_source_id: pdf_source.id
        }
      })

      html = render(view)
      assert html =~ "完了 — 次へ進む"

      # 「次へ進む」ボタンをクリックすると Browse へ遷移
      assert {:error, {:live_redirect, %{to: path}}} =
               view |> element("button", "完了 — 次へ進む") |> render_click()

      assert path =~ "/lab/browse/#{pdf_source.id}"
    end

    test "pdf_source_id無しの完了イベントでは/labへフォールバック", %{conn: conn} do
      pipeline_id = Pipeline.generate_pipeline_id()
      {:ok, view, _html} = live(conn, ~p"/lab/pipeline/#{pipeline_id}")

      # pdf_source_id を含まない完了イベント
      Phoenix.PubSub.broadcast(@pubsub, Pipeline.topic(pipeline_id), {
        :pipeline_progress,
        %{
          event: :pipeline_complete,
          phase: :pdf_extraction,
          total: 1,
          succeeded: 1,
          failed: 0
        }
      })

      render(view)

      assert {:error, {:live_redirect, %{to: "/lab"}}} =
               view |> element("button", "完了 — 次へ進む") |> render_click()
    end
  end
end
