defmodule OmniArchiveWeb.InspectorLive.Finalize do
  @moduledoc """
  ウィザード Step 5: ファイナライズ（レビュー提出）画面。
  Pipeline モジュールを使用して PTIF 生成・IIIF Manifest 登録を非同期で実行し、
  PubSub でリアルタイム進捗を表示します。
  保存完了後に「レビューに提出」ボタンを表示します。
  """
  use OmniArchiveWeb, :live_view

  import OmniArchiveWeb.WizardComponents

  alias OmniArchive.Ingestion
  alias OmniArchive.Pipeline
  alias OmniArchive.Pipeline.ResourceMonitor

  @impl true
  def mount(%{"image_id" => image_id}, _session, socket) do
    case fetch_authorized_image(image_id, socket.assigns.current_user) do
      {:ok, extracted_image} ->
        # パイプラインIDを生成してサブスクライブ
        pipeline_id = Pipeline.generate_pipeline_id()

        if connected?(socket) do
          Phoenix.PubSub.subscribe(OmniArchive.PubSub, Pipeline.topic(pipeline_id))
        end

        # システムリソース情報を取得
        system_info = ResourceMonitor.system_info()

        {:ok,
         socket
         |> assign(:page_title, "保存の確認")
         |> assign(:current_step, 5)
         |> assign(:extracted_image, extracted_image)
         |> assign(:pipeline_id, pipeline_id)
         |> assign(:system_info, system_info)
         |> assign(:processing, false)
         |> assign(:completed, false)
         |> assign(:error_message, nil)
         |> assign(:manifest_identifier, nil)
         |> assign(:progress_tasks, %{})
         |> assign(:overall_progress, 0)}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "指定された画像が見つかりません")
         |> push_navigate(to: ~p"/lab")}
    end
  end

  @impl true
  def handle_event("confirm_save", _params, socket) do
    socket = assign(socket, :processing, true)
    extracted_image = socket.assigns.extracted_image
    pipeline_id = socket.assigns.pipeline_id

    # 非同期でパイプラインを実行
    lv_pid = self()

    Task.start(fn ->
      result = Pipeline.run_single_finalize(extracted_image, pipeline_id)
      send(lv_pid, {:finalize_result, result})
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("submit_for_review", _params, socket) do
    case Ingestion.submit_for_review(socket.assigns.extracted_image) do
      {:ok, updated_image} ->
        {:noreply,
         socket
         |> assign(:extracted_image, updated_image)
         |> put_flash(:info, "レビューに提出しました！管理者の承認をお待ちください。")}

      {:error, :invalid_status_transition} ->
        {:noreply, put_flash(socket, :error, "この画像はレビューに提出できません。")}
    end
  end

  @impl true
  def handle_info({:pipeline_progress, payload}, socket) do
    socket = process_progress(payload, socket)
    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {:finalize_result, {:ok, %{image: updated_image, identifier: identifier}}},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:processing, false)
     |> assign(:completed, true)
     |> assign(:extracted_image, updated_image)
     |> assign(:manifest_identifier, identifier)
     |> assign(:overall_progress, 100)
     |> put_flash(:info, "図版の保存が完了しました！")}
  end

  @impl true
  def handle_info({:finalize_result, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:processing, false)
     |> assign(:error_message, "処理中にエラーが発生しました: #{inspect(reason)}")}
  end

  defp fetch_authorized_image(image_id, current_user) do
    with %{} = image <- Ingestion.get_extracted_image(image_id),
         %{} <- Ingestion.get_pdf_source(image.pdf_source_id, current_user) do
      {:ok, image}
    else
      _ -> :error
    end
  end

  # 進捗イベントの処理
  defp process_progress(%{event: :task_progress} = payload, socket) do
    tasks =
      Map.put(socket.assigns.progress_tasks, payload.task_id, %{
        status: payload.status,
        progress: payload.progress,
        message: payload.message
      })

    socket
    |> assign(:progress_tasks, tasks)
    |> assign(:overall_progress, payload.progress)
  end

  defp process_progress(_payload, socket), do: socket

  # ステータスラベルの日本語表示
  defp status_label("draft"), do: "📝 下書き"
  defp status_label("pending_review"), do: "⏳ レビュー待ち"
  defp status_label("published"), do: "🔒 公開済み"
  defp status_label(_), do: "不明"

  # ステップステータスの絵文字
  defp step_emoji(:completed), do: "✅"
  defp step_emoji(:processing), do: "⚙️"
  defp step_emoji(:error), do: "❌"
  defp step_emoji(_), do: "⏳"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="inspector-container">
      <.wizard_header current_step={@current_step} />

      <div class="finalize-area">
        <%= if @completed do %>
          <%!-- 完了画面 --%>
          <div class="success-card">
            <span class="success-icon">✅</span>
            <h2 class="section-title">保存が完了しました！</h2>
            <p class="section-description">
              図版が正常に処理され、IIIF形式で保存されました。
            </p>

            <%!-- ステータスバッジ --%>
            <div class="status-badge-container">
              <span class={"status-badge status-#{@extracted_image.status}"}>
                {status_label(@extracted_image.status)}
              </span>
            </div>

            <div class="result-info">
              <div class="info-item">
                <span class="info-label">識別子:</span>
                <code class="info-value">{@manifest_identifier}</code>
              </div>
              <div class="info-item">
                <span class="info-label">Manifest URL:</span>
                <a href={"/iiif/manifest/#{@manifest_identifier}"} class="info-link" target="_blank">
                  /iiif/manifest/{@manifest_identifier}
                </a>
              </div>
            </div>

            <div class="action-bar">
              <%= if @extracted_image.status == "draft" do %>
                <button
                  type="button"
                  class="btn-primary btn-large btn-submit-review"
                  phx-click="submit_for_review"
                  aria-label="レビューに提出する"
                >
                  📋 レビューに提出
                </button>
              <% end %>

              <%= if @extracted_image.status == "pending_review" do %>
                <div class="review-submitted-notice" role="status">
                  <span class="notice-icon">⏳</span> レビュー待ちです。管理者の承認をお待ちください。
                </div>
              <% end %>

              <%= if @extracted_image.status == "published" do %>
                <div class="published-notice" role="status">
                  <span class="notice-icon">🔒</span> この図版は公開済みです。
                </div>
              <% end %>

              <.link navigate={~p"/lab"} class="btn-secondary btn-large">
                📤 新しいPDFをアップロード
              </.link>
            </div>
          </div>
        <% else %>
          <%!-- 確認画面 --%>
          <h2 class="section-title">✅ 保存内容の確認</h2>
          <p class="section-description">
            以下の内容で図版を保存します。問題がなければ「保存する」を押してください。
          </p>

          <%!-- システムリソース情報 --%>
          <div class="resource-badge">
            <span class="resource-badge-item">
              🖥️ CPU: {@system_info.cpu_cores}コア
            </span>
            <span class="resource-badge-item">
              💾 利用可能: {Float.round(@system_info.available_memory_bytes / 1_073_741_824, 1)} GB
            </span>
          </div>

          <div class="confirm-card">
            <div class="confirm-item">
              <span class="confirm-label">📄 ページ番号:</span>
              <span class="confirm-value">ページ {@extracted_image.page_number}</span>
            </div>

            <%= if @extracted_image.summary do %>
              <div class="confirm-item">
                <span class="confirm-label">📝 サマリー:</span>
                <span class="confirm-value">{@extracted_image.summary}</span>
              </div>
            <% end %>

            <%= if @extracted_image.label do %>
              <div class="confirm-item">
                <span class="confirm-label">🏷️ ラベル:</span>
                <span class="confirm-value">{@extracted_image.label}</span>
              </div>
            <% end %>

            <%= if @extracted_image.geometry do %>
              <div class="confirm-item">
                <span class="confirm-label">✂️ クロップ範囲:</span>
                <span class="confirm-value">
                  X:{@extracted_image.geometry["x"]},
                  Y:{@extracted_image.geometry["y"]},
                  W:{@extracted_image.geometry["width"]},
                  H:{@extracted_image.geometry["height"]}
                </span>
              </div>
            <% end %>
          </div>

          <%!-- 処理中の進捗表示 --%>
          <%= if @processing do %>
            <div class="finalize-progress">
              <div class="progress-header">
                <span class="progress-label">処理の進捗</span>
                <span class="progress-percentage">{@overall_progress}%</span>
              </div>
              <div
                class="progress-bar-container"
                role="progressbar"
                aria-valuenow={@overall_progress}
                aria-valuemin="0"
                aria-valuemax="100"
              >
                <div class="progress-bar-fill progress-active" style={"width: #{@overall_progress}%"}>
                </div>
              </div>

              <%= for {_id, task} <- @progress_tasks do %>
                <div class="finalize-step">
                  <span class="step-emoji">{step_emoji(task.status)}</span>
                  <span class="step-message">{task.message}</span>
                </div>
              <% end %>
            </div>
          <% end %>

          <%= if @error_message do %>
            <div class="error-message" role="alert">
              <span class="error-icon">⚠️</span>
              {@error_message}
            </div>
          <% end %>

          <div class="action-bar">
            <.link
              navigate={~p"/lab/label/#{@extracted_image.id}"}
              class="btn-secondary btn-large"
            >
              ← 戻る
            </.link>

            <button
              type="button"
              class="btn-primary btn-large btn-confirm"
              phx-click="confirm_save"
              disabled={@processing}
            >
              <%= if @processing do %>
                <span class="spinner"></span> 処理中...
              <% else %>
                💾 保存する
              <% end %>
            </button>
          </div>
        <% end %>
      </div>
    </div>

    <style>
      /* リソースバッジ */
      .resource-badge {
        display: flex;
        gap: 1rem;
        margin-bottom: 1rem;
        flex-wrap: wrap;
      }

      .resource-badge-item {
        background: linear-gradient(135deg, #667eea20, #764ba220);
        border: 1px solid #667eea40;
        border-radius: 999px;
        padding: 0.4rem 1rem;
        font-size: 0.85rem;
        color: #4338ca;
        font-weight: 500;
      }

      /* 進捗表示 */
      .finalize-progress {
        margin: 1.5rem 0;
        padding: 1.25rem;
        background: #f8fafc;
        border-radius: 12px;
        border: 1px solid #e2e8f0;
      }

      .progress-header {
        display: flex;
        justify-content: space-between;
        margin-bottom: 0.5rem;
      }

      .progress-label { font-weight: 600; color: #374151; }
      .progress-percentage { font-weight: 700; color: #667eea; }

      .progress-bar-container {
        width: 100%;
        height: 10px;
        background: #e5e7eb;
        border-radius: 999px;
        overflow: hidden;
        margin-bottom: 1rem;
      }

      .progress-bar-fill {
        height: 100%;
        border-radius: 999px;
        transition: width 0.5s ease-in-out;
      }

      .progress-active {
        background: linear-gradient(90deg, #667eea, #764ba2);
        animation: progress-pulse 2s ease-in-out infinite;
      }

      @keyframes progress-pulse {
        0%, 100% { opacity: 1; }
        50% { opacity: 0.7; }
      }

      .finalize-step {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        padding: 0.5rem 0;
        font-size: 0.9rem;
        color: #374151;
        border-bottom: 1px solid #f1f5f9;
      }

      .finalize-step:last-child { border-bottom: none; }
      .step-emoji { font-size: 1.1rem; }
    </style>
    """
  end
end
