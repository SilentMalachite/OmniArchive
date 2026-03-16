defmodule OmniArchive.PipelineTest do
  @moduledoc """
  Pipeline モジュールのテスト。

  PubSub を活用した進捗ブロードキャストとパイプラインID生成、
  外部コマンド非依存のロジックを検証します。
  """
  use OmniArchive.DataCase, async: false

  alias OmniArchive.Pipeline
  import OmniArchive.Factory

  @pubsub OmniArchive.PubSub

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

      # Task.start だとテスト終了後に Task が残り StaleEntryError が出るため
      # Task.async + await で完了を保証する
      task =
        Task.async(fn ->
          Pipeline.run_pdf_extraction(pdf_source, "/nonexistent/test.pdf", pipeline_id)
        end)

      assert_receive {:pipeline_progress, %{event: :pipeline_started, phase: :pdf_extraction}},
                     5_000

      # Task の完了を待ってから Sandbox がクリーンアップされるようにする
      Task.await(task, 10_000)
    end
  end

  describe "pdf_pipeline_topic/1" do
    test "ユーザーIDからユーザー通知トピック名を生成する" do
      assert Pipeline.pdf_pipeline_topic(123) == "pdf_pipeline:123"
    end

    test "異なるユーザーIDで異なるトピックを返す" do
      topic_a = Pipeline.pdf_pipeline_topic(1)
      topic_b = Pipeline.pdf_pipeline_topic(2)

      refute topic_a == topic_b
    end
  end

  describe "extraction_complete ブロードキャスト" do
    test "成功時に owner_id 指定で {:extraction_complete, pdf_source_id} を配信する" do
      user = insert_user()
      pdf_source = insert_pdf_source(%{status: "uploading", user_id: user.id})
      pipeline_id = Pipeline.generate_pipeline_id()

      # テスト用の最小 PDF をインラインで生成
      # (1ページの空白 PDF — pdftoppm が正常に処理できる)
      pdf_content = """
      %PDF-1.0
      1 0 obj
      << /Type /Catalog /Pages 2 0 R >>
      endobj
      2 0 obj
      << /Type /Pages /Kids [3 0 R] /Count 1 >>
      endobj
      3 0 obj
      << /Type /Page /Parent 2 0 R /MediaBox [0 0 72 72] >>
      endobj
      xref
      0 4
      0000000000 65535 f
      0000000009 00000 n
      0000000058 00000 n
      0000000115 00000 n
      trailer
      << /Size 4 /Root 1 0 R >>
      startxref
      190
      %%EOF
      """

      tmp_pdf =
        Path.join(System.tmp_dir!(), "pipeline_test_#{System.unique_integer([:positive])}.pdf")

      File.write!(tmp_pdf, pdf_content)

      # テスト終了時にクリーンアップ
      output_dir = Path.join(["priv", "static", "uploads", "pages", "#{pdf_source.id}"])

      on_exit(fn ->
        File.rm(tmp_pdf)
        File.rm_rf(output_dir)
      end)

      # ユーザー通知トピックを購読
      Phoenix.PubSub.subscribe(@pubsub, Pipeline.pdf_pipeline_topic(user.id))

      # 同期実行して結果を検証
      result =
        Pipeline.run_pdf_extraction(pdf_source, tmp_pdf, pipeline_id, %{
          owner_id: user.id
        })

      assert {:ok, %{page_count: 1, images: [_image]}} = result

      # 完了通知メッセージを受信
      expected_id = pdf_source.id
      assert_receive {:extraction_complete, ^expected_id}, 5_000
    end

    test "エラー時は owner_id 指定でも {:extraction_complete, _} を配信しない" do
      user = insert_user()
      pdf_source = insert_pdf_source(%{status: "uploading", user_id: user.id})
      pipeline_id = Pipeline.generate_pipeline_id()

      # ユーザー通知トピックを購読
      Phoenix.PubSub.subscribe(@pubsub, Pipeline.pdf_pipeline_topic(user.id))

      # Task.start だとテスト終了後に Task が残り StaleEntryError が出るため
      # Task.async + await で完了を保証する
      task =
        Task.async(fn ->
          Pipeline.run_pdf_extraction(pdf_source, "/nonexistent/test.pdf", pipeline_id, %{
            owner_id: user.id
          })
        end)

      # Task の完了を待ってから refute する
      Task.await(task, 10_000)

      # PDF が存在しないためエラーパスに入り、extraction_complete は配信されない
      refute_receive {:extraction_complete, _}, 500
    end

    test "owner_id 未指定時に {:extraction_complete, _} を配信しない" do
      pdf_source = insert_pdf_source(%{status: "uploading"})
      pipeline_id = Pipeline.generate_pipeline_id()

      # パイプライントピックを購読
      Phoenix.PubSub.subscribe(@pubsub, Pipeline.topic(pipeline_id))

      Task.start(fn ->
        Pipeline.run_pdf_extraction(pdf_source, "/nonexistent/test.pdf", pipeline_id)
      end)

      # パイプライン進捗イベントは受信するが、extraction_complete は受信しない
      assert_receive {:pipeline_progress, %{event: :pipeline_started}}, 5_000
      refute_receive {:extraction_complete, _}, 1_000
    end
  end
end
