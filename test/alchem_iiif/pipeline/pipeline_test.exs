defmodule AlchemIiif.PipelineTest do
  @moduledoc """
  Pipeline モジュールのテスト。

  PubSub を活用した進捗ブロードキャストとパイプラインID生成、
  外部コマンド非依存のロジックを検証します。
  """
  use AlchemIiif.DataCase, async: false

  alias AlchemIiif.Pipeline
  import AlchemIiif.Factory

  @pubsub AlchemIiif.PubSub

  describe "topic/1" do
    test "パイプラインIDからトピック名を生成する" do
      assert Pipeline.topic("pl-12345") == "pipeline:pl-12345"
    end

    test "異なるIDで異なるトピックを返す" do
      topic_a = Pipeline.topic("pl-aaa")
      topic_b = Pipeline.topic("pl-bbb")

      refute topic_a == topic_b
    end
  end

  describe "generate_pipeline_id/0" do
    test "文字列のパイプラインIDを返す" do
      id = Pipeline.generate_pipeline_id()

      assert is_binary(id)
      assert String.starts_with?(id, "pl-")
    end

    test "呼び出すたびにユニークなIDを返す" do
      ids = for _ <- 1..10, do: Pipeline.generate_pipeline_id()
      unique_ids = Enum.uniq(ids)

      assert length(unique_ids) == length(ids)
    end
  end

  describe "PubSub ブロードキャスト" do
    test "run_single_finalize がパイプライン開始イベントをブロードキャストする" do
      # テスト用の ExtractedImage を作成
      image =
        insert_extracted_image(%{
          image_path: "priv/static/uploads/pages/test/nonexistent.png"
        })

      pipeline_id = Pipeline.generate_pipeline_id()

      # PubSub をサブスクライブ
      Phoenix.PubSub.subscribe(@pubsub, Pipeline.topic(pipeline_id))

      # 非同期で実行（PTIF生成は失敗するが、ブロードキャストは確認できる）
      Task.start(fn ->
        Pipeline.run_single_finalize(image, pipeline_id)
      end)

      # パイプライン開始イベントを受信
      assert_receive {:pipeline_progress, %{event: :pipeline_started, phase: :finalize}}, 5_000
    end

    test "run_single_finalize が PTIF 生成のタスク進捗をブロードキャストする" do
      image =
        insert_extracted_image(%{
          image_path: "priv/static/uploads/pages/test/nonexistent.png"
        })

      pipeline_id = Pipeline.generate_pipeline_id()

      Phoenix.PubSub.subscribe(@pubsub, Pipeline.topic(pipeline_id))

      Task.start(fn ->
        Pipeline.run_single_finalize(image, pipeline_id)
      end)

      # PTIF 生成のタスク進捗イベントを受信
      assert_receive {:pipeline_progress,
                      %{event: :task_progress, task_id: "finalize-ptif", status: :processing}},
                     5_000
    end

    test "PTIF 生成失敗時にエラーステータスをブロードキャストする" do
      image =
        insert_extracted_image(%{
          image_path: "priv/static/uploads/pages/test/nonexistent.png"
        })

      pipeline_id = Pipeline.generate_pipeline_id()

      Phoenix.PubSub.subscribe(@pubsub, Pipeline.topic(pipeline_id))

      Task.start(fn ->
        Pipeline.run_single_finalize(image, pipeline_id)
      end)

      # 存在しないファイルのため PTIF 生成が失敗 → エラー進捗
      assert_receive {:pipeline_progress,
                      %{event: :task_progress, task_id: "finalize-ptif", status: :error}},
                     10_000
    end
  end

  describe "run_single_finalize/2" do
    test "存在しない画像ファイルの場合はエラーを返す" do
      image =
        insert_extracted_image(%{
          image_path: "priv/static/uploads/pages/test/nonexistent.png"
        })

      pipeline_id = Pipeline.generate_pipeline_id()

      # PubSub をサブスクライブ（ブロードキャスト用）
      Phoenix.PubSub.subscribe(@pubsub, Pipeline.topic(pipeline_id))

      result = Pipeline.run_single_finalize(image, pipeline_id)

      assert {:error, _reason} = result
    end
  end

  describe "run_pdf_extraction/3" do
    test "存在しない PDF パスの場合はエラーを返す" do
      pdf_source = insert_pdf_source(%{status: "uploading"})
      pipeline_id = Pipeline.generate_pipeline_id()

      Phoenix.PubSub.subscribe(@pubsub, Pipeline.topic(pipeline_id))

      result = Pipeline.run_pdf_extraction(pdf_source, "/nonexistent/test.pdf", pipeline_id)

      assert {:error, _reason} = result
    end

    test "PDF 抽出開始時にパイプライン開始イベントをブロードキャストする" do
      pdf_source = insert_pdf_source(%{status: "uploading"})
      pipeline_id = Pipeline.generate_pipeline_id()

      Phoenix.PubSub.subscribe(@pubsub, Pipeline.topic(pipeline_id))

      Task.start(fn ->
        Pipeline.run_pdf_extraction(pdf_source, "/nonexistent/test.pdf", pipeline_id)
      end)

      assert_receive {:pipeline_progress, %{event: :pipeline_started, phase: :pdf_extraction}},
                     5_000
    end
  end
end
