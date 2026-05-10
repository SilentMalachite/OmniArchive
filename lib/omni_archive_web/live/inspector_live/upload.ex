defmodule OmniArchiveWeb.InspectorLive.Upload do
  @moduledoc """
  ウィザード Step 1: ソース（PDF / ZIP）アップロード画面 + 要修正タブ。
  PDF または PNG 入り ZIP をアップロードし、並列パイプラインで自動的に
  ページ画像へ展開します。差し戻された画像の一覧も表示し、修正・再提出
  ワークフローを提供します。
  """
  use OmniArchiveWeb, :live_view

  import OmniArchiveWeb.WizardComponents

  alias OmniArchive.Ingestion
  alias OmniArchive.Pipeline
  alias OmniArchive.Workers.UserWorker

  @daily_upload_limit 20
  @upload_quota_window_seconds 24 * 60 * 60
  @default_estimated_page_count 200
  @min_estimated_page_count 1
  # 取り込み容量・ページ上限のフォールバック（runtime.exs で上書き）
  @fallback_max_source_upload_bytes 500_000_000
  @fallback_max_pages 1500

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user

    # WebSocket 接続時のみユーザー単位の完了通知を購読
    if connected?(socket) do
      Phoenix.PubSub.subscribe(
        OmniArchive.PubSub,
        Pipeline.pdf_pipeline_topic(current_user.id)
      )
    end

    rejected_images = Ingestion.list_rejected_images(current_user)

    max_estimated_page_count = ingestion_max_pages()
    max_source_upload_bytes = ingestion_max_upload_bytes()

    {:ok,
     socket
     |> assign(:page_title, "ソースをアップロード")
     |> assign(:current_step, 1)
     |> assign(:uploading, false)
     |> assign(:error_message, nil)
     |> assign(:active_tab, :upload)
     |> assign(:rejected_images, rejected_images)
     |> assign(:rejected_count, length(rejected_images))
     |> assign(:current_page, 0)
     |> assign(:total_pages, 0)
     |> assign(:color_mode, "mono")
     |> assign(:estimated_page_count, default_estimated_page_count(max_estimated_page_count))
     |> assign(:min_estimated_page_count, @min_estimated_page_count)
     |> assign(:max_estimated_page_count, max_estimated_page_count)
     |> assign(:max_source_upload_bytes, max_source_upload_bytes)
     |> allow_upload(:source,
       accept: ~w(.pdf .zip),
       max_entries: 1,
       max_file_size: max_source_upload_bytes
     )}
  end

  @impl true
  def handle_event("validate", params, socket) do
    color_mode = get_in(params, ["color_mode"]) || socket.assigns.color_mode
    estimated_page_count = parse_estimated_page_count(params["estimated_page_count"])

    {:noreply,
     socket
     |> assign(:color_mode, color_mode)
     |> assign(:estimated_page_count, estimated_page_count)}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    case tab do
      "upload" -> {:noreply, assign(socket, :active_tab, :upload)}
      "rejected" -> {:noreply, assign(socket, :active_tab, :rejected)}
      _ -> {:noreply, socket}
    end
  end

  @impl true
  # セキュリティ注記: upload_dir は固定パス（PDF: priv/static/uploads/pdfs,
  # ZIP: priv/static/uploads/sources）、path は Phoenix LiveView の一時ファイル、
  # dest は内部生成で安全。
  def handle_event("upload_source", params, socket) do
    color_mode = get_in(params, ["color_mode"]) || socket.assigns.color_mode
    estimated_page_count = parse_estimated_page_count(params["estimated_page_count"])

    case validate_upload_quota(socket.assigns.current_user) do
      :ok ->
        socket =
          assign(socket,
            uploading: true,
            color_mode: color_mode,
            estimated_page_count: estimated_page_count
          )

        handle_source_upload(socket)

      {:error, message} ->
        {:noreply,
         socket
         |> assign(:uploading, false)
         |> assign(:color_mode, color_mode)
         |> assign(:estimated_page_count, estimated_page_count)
         |> assign(:error_message, message)
         |> put_flash(:error, message)}
    end
  end

  @impl true
  def handle_info({:extraction_progress, current, total}, socket) do
    {:noreply, assign(socket, current_page: current, total_pages: total)}
  end

  @impl true
  def handle_info({:extraction_complete, document_id}, socket) do
    {:noreply,
     socket
     |> assign(:uploading, false)
     |> assign(:current_page, 0)
     |> assign(:total_pages, 0)
     |> put_flash(:info, "PDFの処理が完了しました！")
     |> push_navigate(to: ~p"/lab/browse/#{document_id}")}
  end

  @impl true
  def handle_info({:pdf_processed, pdf_source_id}, socket) do
    if socket.assigns[:processing_pdf_id] == pdf_source_id do
      {:noreply,
       socket
       |> assign(:uploading, false)
       |> put_flash(:info, "PDFの処理が完了しました！")
       |> push_navigate(to: ~p"/lab/browse/#{pdf_source_id}")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="inspector-container">
      <.wizard_header current_step={@current_step} />

      <%!-- タブナビゲーション --%>
      <div class="lab-tabs">
        <button
          type="button"
          class={"lab-tab #{if @active_tab == :upload, do: "lab-tab-active", else: ""}"}
          phx-click="switch_tab"
          phx-value-tab="upload"
        >
          📤 アップロード
        </button>
        <button
          type="button"
          class={"lab-tab #{if @active_tab == :rejected, do: "lab-tab-active", else: ""} #{if @rejected_count > 0, do: "lab-tab-alert", else: ""}"}
          phx-click="switch_tab"
          phx-value-tab="rejected"
        >
          ⚠️ 要修正
          <%= if @rejected_count > 0 do %>
            <span class="tab-badge">{@rejected_count}</span>
          <% end %>
        </button>
      </div>

      <%!-- アップロードタブ --%>
      <%= if @active_tab == :upload do %>
        <div class="upload-area">
          <h2 class="section-title">ソースファイルをアップロード</h2>
          <p class="section-description">
            アーカイブする PDF または PNG 入り ZIP ファイルを選択してください。
          </p>

          <form id="upload-form" phx-submit="upload_source" phx-change="validate">
            <%!-- カラーモード切替ラジオボタン --%>
            <div class="color-mode-selector">
              <span class="color-mode-label">変換モード:</span>
              <label class={"color-mode-option #{if @color_mode == "mono", do: "selected", else: ""}"}>
                <input
                  type="radio"
                  name="color_mode"
                  value="mono"
                  checked={@color_mode == "mono"}
                /> 🖤 モノクロモード（高速）
              </label>
              <label class={"color-mode-option #{if @color_mode == "color", do: "selected", else: ""}"}>
                <input
                  type="radio"
                  name="color_mode"
                  value="color"
                  checked={@color_mode == "color"}
                /> 🎨 カラーモード（標準）
              </label>
            </div>

            <div class="grid grid-cols-1 gap-3 rounded-xl border border-base-300 bg-base-100 p-4 mb-6 sm:grid-cols-[max-content_minmax(7rem,10rem)_1fr] sm:items-center">
              <label for="estimated-page-count" class="text-sm font-bold text-base-content">
                PDFページ数の目安
              </label>
              <input
                type="number"
                id="estimated-page-count"
                name="estimated_page_count"
                min={@min_estimated_page_count}
                max={@max_estimated_page_count}
                step="1"
                value={@estimated_page_count}
                class="input input-bordered w-full font-semibold"
              />
              <span class="text-xs text-base-content/60">
                実際のページ数がこの値を超えるソースは処理を止めます。
              </span>
            </div>

            <div class="upload-dropzone" phx-drop-target={@uploads.source.ref}>
              <.live_file_input upload={@uploads.source} class="file-input" />
              <div class="dropzone-content">
                <span class="dropzone-icon">📄</span>
                <span class="dropzone-text">
                  ここに PDF または ZIP をドラッグ、またはクリックして選択
                </span>
              </div>
            </div>

            <%= for entry <- @uploads.source.entries do %>
              <div class="upload-entry">
                <span class="entry-name">{entry.client_name}</span>
                <progress value={entry.progress} max="100" class="upload-progress">
                  {entry.progress}%
                </progress>
              </div>

              <%!-- エントリ単位のアップロードエラー表示 --%>
              <%= for err <- upload_errors(@uploads.source, entry) do %>
                <div class="error-message" role="alert">
                  <span class="error-icon">⚠️</span>
                  {translate_upload_error(err)}
                </div>
              <% end %>
            <% end %>

            <%!-- 全体のアップロードエラー表示 --%>
            <%= for err <- upload_errors(@uploads.source) do %>
              <div class="error-message" role="alert">
                <span class="error-icon">⚠️</span>
                {translate_upload_error(err)}
              </div>
            <% end %>

            <%= if @error_message do %>
              <div class="error-message" role="alert">
                <span class="error-icon">⚠️</span>
                {@error_message}
              </div>
            <% end %>

            <button
              type="submit"
              class="btn-primary btn-large"
              disabled={@uploading || @uploads.source.entries == []}
            >
              <%= if @uploading do %>
                <span class="spinner"></span> アップロード中...
              <% else %>
                📤 アップロードして変換する
              <% end %>
            </button>

            <%= if @uploading && @total_pages > 0 do %>
              <div class="mt-4">
                <div class="flex justify-between mb-1">
                  <span class="text-sm font-medium text-gray-700">ソースを読み込み中...</span>
                  <span class="text-sm font-medium text-gray-700">
                    {@current_page} / {@total_pages} ページ
                  </span>
                </div>
                <div class="w-full bg-gray-200 rounded-full h-2.5">
                  <div
                    class="bg-blue-600 h-2.5 rounded-full transition-all duration-500"
                    style={"width: #{trunc(@current_page / max(@total_pages, 1) * 100)}%"}
                  >
                  </div>
                </div>
              </div>
            <% end %>
          </form>
        </div>
      <% end %>

      <%!-- 要修正タブ --%>
      <%= if @active_tab == :rejected do %>
        <div class="rejected-area">
          <h2 class="section-title">⚠️ 要修正の図版</h2>
          <p class="section-description">
            レビューで差し戻された図版です。修正して再提出してください。
          </p>

          <%= if @rejected_images == [] do %>
            <div class="no-results">
              <span class="no-results-icon">✅</span>
              <p class="section-description">
                差し戻された図版はありません。すべて処理済みです！
              </p>
            </div>
          <% else %>
            <div class="rejected-list">
              <%= for image <- @rejected_images do %>
                <div class="rejected-card" id={"rejected-card-#{image.id}"}>
                  <%!-- Row 1: メタ情報 & アクション --%>
                  <div class="rejected-card-row1">
                    <div class="rejected-card-info">
                      <span class="rejected-card-label">{image.label || "名称未設定"}</span>
                      <%= if image.pdf_source do %>
                        <span class="meta-tag">📄 {image.pdf_source.filename}</span>
                      <% end %>
                      <span class="meta-tag">P.{image.page_number}</span>
                    </div>
                    <.link
                      navigate={~p"/lab/label/#{image.id}"}
                      class="btn-resubmit-sm"
                    >
                      🔧 修正する
                    </.link>
                  </div>
                  <%!-- Row 2: レビューコメント（存在する場合のみ） --%>
                  <%= if image.review_comment && image.review_comment != "" do %>
                    <div class="rejected-card-comment">
                      {image.review_comment}
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # アップロードされたソース（PDF / ZIP）を保存ディレクトリに永続化し、
  # source_type をファイル拡張子から判定してパイプラインを起動する。
  defp handle_source_upload(socket) do
    uploaded =
      consume_uploaded_entries(socket, :source, fn %{path: path}, entry ->
        ext = entry.client_name |> Path.extname() |> String.downcase()
        source_type = source_type_for_extension(ext)
        upload_dir = upload_dir_for(source_type)
        File.mkdir_p!(upload_dir)

        timestamp = System.system_time(:second)
        base = Path.basename(entry.client_name, ext)
        versioned_name = "#{base}-#{timestamp}#{ext}"
        dest = Path.join(upload_dir, versioned_name)
        File.cp!(path, dest)
        {:ok, {source_type, dest}}
      end)

    case uploaded do
      [{source_type, source_path}] ->
        start_source_processing(socket, source_type, source_path)

      _ ->
        {:noreply,
         socket
         |> assign(:uploading, false)
         |> assign(:error_message, "PDF または ZIP ファイルを選択してください")}
    end
  end

  defp source_type_for_extension(".zip"), do: "zip"
  defp source_type_for_extension(_), do: "pdf"

  defp upload_dir_for("zip"), do: Path.join(["priv", "static", "uploads", "sources"])
  defp upload_dir_for(_), do: Path.join(["priv", "static", "uploads", "pdfs"])

  defp start_source_processing(socket, source_type, source_path) do
    # ソースレコードを作成
    {:ok, pdf_source} =
      Ingestion.create_pdf_source(%{
        filename: Path.basename(source_path),
        source_type: source_type,
        status: "converting",
        user_id: socket.assigns.current_user.id
      })

    pipeline_id = Pipeline.generate_pipeline_id()
    owner_id = socket.assigns.current_user.id

    case UserWorker.process_source(
           owner_id,
           pdf_source,
           source_path,
           pipeline_id,
           %{
             color_mode: socket.assigns.color_mode,
             max_pages: socket.assigns.estimated_page_count
           }
         ) do
      :ok ->
        Phoenix.PubSub.subscribe(OmniArchive.PubSub, "pdf_source_#{pdf_source.id}")

        {:noreply,
         socket
         |> assign(:uploading, true)
         |> assign(:processing_pdf_id, pdf_source.id)
         |> put_flash(
           :info,
           "裏側でソース処理を開始しました。完了するまでこの画面でお待ちください..."
         )}

      {:error, :pdf_job_in_progress} ->
        Ingestion.update_pdf_source(pdf_source, %{status: "error"})
        File.rm(source_path)

        message = "処理中のソースがあります。完了してから次のソースをアップロードしてください。"

        {:noreply,
         socket
         |> assign(:uploading, false)
         |> assign(:error_message, message)
         |> put_flash(:error, message)}
    end
  end

  defp validate_upload_quota(current_user) do
    cond do
      Ingestion.count_active_pdf_sources(current_user) > 0 ->
        {:error, "処理中のソースがあります。完了してから次のソースをアップロードしてください。"}

      Ingestion.count_recent_pdf_sources(current_user, upload_quota_window_start()) >=
          @daily_upload_limit ->
        {:error,
         "1日のアップロード上限（#{@daily_upload_limit}件）に達しました。時間をおいて再試行してください。"}

      true ->
        :ok
    end
  end

  defp upload_quota_window_start do
    DateTime.utc_now(:second)
    |> DateTime.add(-@upload_quota_window_seconds, :second)
  end

  defp parse_estimated_page_count(value) do
    max_pages = ingestion_max_pages()
    fallback = default_estimated_page_count(max_pages)

    case Integer.parse(to_string(value || fallback)) do
      {page_count, ""} ->
        page_count
        |> max(@min_estimated_page_count)
        |> min(max_pages)

      _ ->
        fallback
    end
  end

  # 集約された取り込み設定（config :omni_archive, :ingestion）から最大ページ数を取得
  defp ingestion_max_pages do
    case Application.get_env(:omni_archive, :ingestion) do
      nil -> @fallback_max_pages
      ingestion -> Keyword.get(ingestion, :pdf_max_pages, @fallback_max_pages)
    end
  end

  defp ingestion_max_upload_bytes do
    case Application.get_env(:omni_archive, :ingestion) do
      nil -> @fallback_max_source_upload_bytes
      ingestion -> Keyword.get(ingestion, :max_source_upload_bytes, @fallback_max_source_upload_bytes)
    end
  end

  # UI 上の「目安」初期値は、最大値が小さいときは最大値を、十分大きければ既定 200 を返す。
  defp default_estimated_page_count(max_pages) do
    min(@default_estimated_page_count, max_pages)
  end

  defp translate_upload_error(:too_large) do
    mb = div(ingestion_max_upload_bytes(), 1_000_000)
    "ファイルサイズが上限（#{mb}MB）を超えています。"
  end


  defp translate_upload_error(:too_many_files), do: "アップロードできるファイルは1つだけです。"
  defp translate_upload_error(:not_accepted), do: "PDF または ZIP ファイルのみアップロード可能です。"
  defp translate_upload_error(err), do: "アップロードエラー: #{inspect(err)}"
end
