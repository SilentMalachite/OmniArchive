defmodule AlchemIiif.Pipeline do
  @moduledoc """
  リソース認識型並列処理パイプラインのオーケストレーションモジュール。

  Task.async_stream を使用して PDF 抽出・PTIF 変換を並列化し、
  PubSub でリアルタイム進捗をブロードキャストします。

  ## なぜこの設計か

  - **Task.async_stream**: GenStage や Broadway と比較して、バッチ処理には
    Task.async_stream がシンプルで適しています。考古学資料のバッチサイズは
    通常数十〜数百件のため、バックプレッシャー制御よりも簡潔さを優先しました。
  - **PubSub リアルタイム進捗**: PTIF 生成は1件あたり数秒〜数十秒かかるため、
    ユーザーに「処理が進んでいる」フィードバックを返すことが認知的に重要です。
    LiveView の PubSub 統合により、サーバープッシュで即座に UI を更新します。
  - **ResourceMonitor 連携**: 同時実行数を動的に制限することで、メモリ不足による
    OOM Kill を防ぎつつ、利用可能なリソースを最大限活用します。
  """
  require Logger

  alias AlchemIiif.IIIF.Manifest
  alias AlchemIiif.Ingestion
  alias AlchemIiif.Ingestion.{ImageProcessor, PdfProcessor}
  alias AlchemIiif.Pipeline.ResourceMonitor
  alias AlchemIiif.Repo
  alias Phoenix.PubSub

  @pubsub AlchemIiif.PubSub

  # --- 公開 API ---

  @doc """
  パイプラインの PubSub トピック名を返します。
  """
  def topic(pipeline_id), do: "pipeline:#{pipeline_id}"

  @doc """
  PDF を PNG に変換し、抽出画像を並列で DB に登録します。

  ## 引数
    - pdf_source: PdfSource レコード
    - pdf_path: PDF ファイルのパス
    - pipeline_id: パイプライン識別子
    - opts: オプション（owner_id など）

  ## 戻り値
    - {:ok, %{page_count: integer, images: [ExtractedImage.t()]}}
    - {:error, reason}
  """
  def run_pdf_extraction(pdf_source, pdf_path, pipeline_id, opts \\ %{}) do
    broadcast_progress(pipeline_id, %{
      event: :pipeline_started,
      phase: :pdf_extraction,
      message: "PDF変換を開始します..."
    })

    # 並行安全: ジョブごとにユニークな一時ディレクトリを使用
    job_id = Ecto.UUID.generate()
    tmp_dir = Path.join(System.tmp_dir!(), "alchemiiif_job_#{job_id}")
    # 最終出力先
    output_dir = Path.join(["priv", "static", "uploads", "pages", "#{pdf_source.id}"])
    File.mkdir_p!(output_dir)

    Logger.info(
      "[Pipeline] PDF extraction started: #{pdf_path} -> tmp:#{tmp_dir} -> #{output_dir}"
    )

    try do
      case PdfProcessor.convert_to_images(pdf_path, tmp_dir) do
        {:ok, %{page_count: page_count, image_paths: tmp_image_paths}} ->
          # 一時ディレクトリから最終出力先へファイルを移動
          image_paths =
            Enum.map(tmp_image_paths, fn tmp_path ->
              filename = Path.basename(tmp_path)
              final_path = Path.join(output_dir, filename)
              File.cp!(tmp_path, final_path)
              final_path
            end)

          # PdfSource を更新
          {:ok, _} =
            Ingestion.update_pdf_source(pdf_source, %{
              page_count: page_count,
              status: "ready"
            })

          broadcast_progress(pipeline_id, %{
            event: :phase_complete,
            phase: :pdf_extraction,
            message: "PDF変換完了: #{page_count}ページ",
            total: page_count
          })

          # 並列で ExtractedImage レコードを DB に登録
          concurrency = ResourceMonitor.pipeline_concurrency()

          images =
            image_paths
            |> Enum.with_index(1)
            |> Task.async_stream(
              fn {image_path, page_number} ->
                {:ok, image} =
                  Ingestion.create_extracted_image(
                    %{
                      pdf_source_id: pdf_source.id,
                      page_number: page_number,
                      image_path: image_path
                    }
                    |> maybe_put_owner_id(opts)
                  )

                broadcast_progress(pipeline_id, %{
                  event: :task_progress,
                  task_id: "page-#{page_number}",
                  status: :completed,
                  progress: round(page_number / page_count * 100),
                  message: "ページ #{page_number} を登録しました"
                })

                image
              end,
              max_concurrency: concurrency,
              timeout: 60_000
            )
            |> Enum.map(fn {:ok, image} -> image end)

          broadcast_progress(pipeline_id, %{
            event: :pipeline_complete,
            phase: :pdf_extraction,
            total: page_count,
            succeeded: length(images),
            failed: 0,
            pdf_source_id: pdf_source.id
          })

          {:ok, %{page_count: page_count, images: images}}

        {:error, reason} ->
          Ingestion.update_pdf_source(pdf_source, %{status: "error"})

          broadcast_progress(pipeline_id, %{
            event: :pipeline_error,
            phase: :pdf_extraction,
            message: "PDF変換に失敗しました: #{reason}"
          })

          {:error, reason}
      end
    after
      # 一時ディレクトリを確実に削除（並行安全のクリーンアップ）
      File.rm_rf(tmp_dir)
      Logger.info("[Pipeline] Cleaned up temp directory: #{tmp_dir}")
    end
  end

  @doc """
  複数画像の PTIF 生成を並列で実行します（メモリガード付き）。

  ## 引数
    - extracted_images: ExtractedImage レコードのリスト
    - pipeline_id: パイプライン識別子

  ## 戻り値
    - {:ok, %{total: integer, succeeded: integer, failed: integer, results: list}}
  """
  def run_ptif_generation(extracted_images, pipeline_id) do
    total = length(extracted_images)
    # メモリガードで同時実行数を制限
    max_workers = ResourceMonitor.max_ptif_workers()

    Logger.info("[Pipeline] PTIF生成開始: #{total}件, 最大同時実行数: #{max_workers}")

    broadcast_progress(pipeline_id, %{
      event: :pipeline_started,
      phase: :ptif_generation,
      message: "PTIF生成を開始します（#{total}件, 並列度: #{max_workers}）...",
      total: total
    })

    results =
      extracted_images
      |> Enum.with_index(1)
      |> Task.async_stream(
        fn {image, index} ->
          task_id = "ptif-#{image.id}"

          broadcast_progress(pipeline_id, %{
            event: :task_progress,
            task_id: task_id,
            status: :processing,
            progress: 0,
            message: "PTIF生成中: ページ #{image.page_number}"
          })

          result = generate_single_ptif(image)

          case result do
            {:ok, _updated_image} ->
              broadcast_progress(pipeline_id, %{
                event: :task_progress,
                task_id: task_id,
                status: :completed,
                progress: round(index / total * 100),
                message: "PTIF生成完了: ページ #{image.page_number}"
              })

            {:error, reason} ->
              broadcast_progress(pipeline_id, %{
                event: :task_progress,
                task_id: task_id,
                status: :error,
                progress: round(index / total * 100),
                message: "PTIF生成失敗: #{inspect(reason)}"
              })
          end

          {image.id, result}
        end,
        max_concurrency: max_workers,
        timeout: 300_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    succeeded = Enum.count(results, fn {_id, res} -> match?({:ok, _}, res) end)
    failed = total - succeeded

    broadcast_progress(pipeline_id, %{
      event: :pipeline_complete,
      phase: :ptif_generation,
      total: total,
      succeeded: succeeded,
      failed: failed
    })

    {:ok, %{total: total, succeeded: succeeded, failed: failed, results: results}}
  end

  @doc """
  単一画像のクロップ → PTIF → Manifest 生成を実行します。
  FinalizeのLiveViewから呼ばれます。

  ## 引数
    - extracted_image: ExtractedImage レコード
    - pipeline_id: パイプライン識別子

  ## 戻り値
    - {:ok, %{image: ExtractedImage.t(), identifier: String.t()}}
    - {:error, reason}
  """
  def run_single_finalize(extracted_image, pipeline_id) do
    broadcast_progress(pipeline_id, %{
      event: :pipeline_started,
      phase: :finalize,
      message: "ファイナライズを開始します...",
      total: 3
    })

    # ステップ1: PTIF生成
    broadcast_progress(pipeline_id, %{
      event: :task_progress,
      task_id: "finalize-ptif",
      status: :processing,
      progress: 0,
      message: "PTIF生成中..."
    })

    case generate_single_ptif(extracted_image) do
      {:ok, updated_image} ->
        broadcast_progress(pipeline_id, %{
          event: :task_progress,
          task_id: "finalize-ptif",
          status: :completed,
          progress: 33,
          message: "PTIF生成完了"
        })

        # ステップ2: Manifest生成
        broadcast_progress(pipeline_id, %{
          event: :task_progress,
          task_id: "finalize-manifest",
          status: :processing,
          progress: 33,
          message: "IIIF Manifest生成中..."
        })

        identifier = "img-#{extracted_image.id}-#{:rand.uniform(99999)}"

        case create_manifest(extracted_image, identifier) do
          {:ok, _manifest} ->
            broadcast_progress(pipeline_id, %{
              event: :task_progress,
              task_id: "finalize-manifest",
              status: :completed,
              progress: 100,
              message: "IIIF Manifest生成完了"
            })

            broadcast_progress(pipeline_id, %{
              event: :pipeline_complete,
              phase: :finalize,
              total: 2,
              succeeded: 2,
              failed: 0
            })

            {:ok, %{image: updated_image, identifier: identifier}}

          {:error, reason} ->
            broadcast_progress(pipeline_id, %{
              event: :task_progress,
              task_id: "finalize-manifest",
              status: :error,
              progress: 66,
              message: "Manifest生成失敗"
            })

            {:error, reason}
        end

      {:error, reason} ->
        broadcast_progress(pipeline_id, %{
          event: :task_progress,
          task_id: "finalize-ptif",
          status: :error,
          progress: 0,
          message: "PTIF生成に失敗しました"
        })

        {:error, reason}
    end
  end

  @doc "ユニークなパイプラインIDを生成します。"
  def generate_pipeline_id do
    "pl-#{System.system_time(:millisecond)}-#{:rand.uniform(99999)}"
  end

  # --- プライベート関数 ---

  @doc """
  単一画像のPTIF生成（クロップ処理込み）。
  Label 提出時のバックグラウンド呼び出しにも使用されます。

  セキュリティ注記: ptif_dir / cropped_path は内部生成パス（priv/static/iiif_images）で安全。
  """
  def generate_single_ptif(extracted_image) do
    ptif_dir = Path.join(["priv", "static", "iiif_images"])
    File.mkdir_p!(ptif_dir)

    identifier = "img-#{extracted_image.id}-#{:rand.uniform(99999)}"
    ptif_path = Path.join(ptif_dir, "#{identifier}.tif")

    result =
      if extracted_image.geometry do
        # クロップ画像を一時ファイルに保存してからPTIF変換
        cropped_path = Path.join(ptif_dir, "#{identifier}_cropped.png")

        with :ok <-
               ImageProcessor.crop_image(
                 extracted_image.image_path,
                 extracted_image.geometry,
                 cropped_path
               ),
             :ok <- ImageProcessor.generate_ptif(cropped_path, ptif_path) do
          File.rm(cropped_path)
          :ok
        end
      else
        ImageProcessor.generate_ptif(extracted_image.image_path, ptif_path)
      end

    case result do
      :ok ->
        Ingestion.update_extracted_image(extracted_image, %{ptif_path: ptif_path})

      error ->
        error
    end
  end

  # IIIF Manifest レコードの作成
  defp create_manifest(extracted_image, identifier) do
    %Manifest{}
    |> Manifest.changeset(%{
      extracted_image_id: extracted_image.id,
      identifier: identifier,
      metadata: %{
        "label" => %{
          "en" => [extracted_image.label || identifier],
          "ja" => [extracted_image.label || identifier]
        },
        "summary" => %{
          "en" => [extracted_image.caption || ""],
          "ja" => [extracted_image.caption || ""]
        }
      }
    })
    |> Repo.insert()
  end

  # PubSub で進捗をブロードキャスト
  defp broadcast_progress(pipeline_id, payload) do
    PubSub.broadcast(@pubsub, topic(pipeline_id), {:pipeline_progress, payload})
  end

  # opts に owner_id が含まれている場合は attrs に追加
  defp maybe_put_owner_id(attrs, %{owner_id: owner_id}) when not is_nil(owner_id) do
    Map.put(attrs, :owner_id, owner_id)
  end

  defp maybe_put_owner_id(attrs, _opts), do: attrs
end
