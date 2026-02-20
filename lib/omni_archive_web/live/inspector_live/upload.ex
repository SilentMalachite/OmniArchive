defmodule OmniArchiveWeb.InspectorLive.Upload do
  @moduledoc """
  ウィザード Step 1: PDF アップロード画面 + 要修正タブ。
  PDFファイルをアップロードし、並列パイプラインで自動的にPNG画像に変換します。
  差し戻された画像の一覧も表示し、修正・再提出ワークフローを提供します。
  """
  use OmniArchiveWeb, :live_view

  import OmniArchiveWeb.WizardComponents

  alias OmniArchive.Ingestion
  alias OmniArchive.Pipeline

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user
    rejected_images = Ingestion.list_rejected_images(current_user)

    {:ok,
     socket
     |> assign(:page_title, "PDF をアップロード")
     |> assign(:current_step, 1)
     |> assign(:uploading, false)
     |> assign(:error_message, nil)
     |> assign(:active_tab, :upload)
     |> assign(:rejected_images, rejected_images)
     |> assign(:rejected_count, length(rejected_images))
     |> allow_upload(:pdf, accept: ~w(.pdf), max_entries: 1, max_file_size: 500_000_000)}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, String.to_existing_atom(tab))}
  end

  @impl true
  # セキュリティ注記: upload_dir は固定パス（priv/static/uploads/pdfs）、
  # path は Phoenix LiveView の一時ファイル、dest は内部生成で安全。
  def handle_event("upload_pdf", _params, socket) do
    socket = assign(socket, :uploading, true)

    uploaded_files =
      consume_uploaded_entries(socket, :pdf, fn %{path: path}, entry ->
        # アップロードディレクトリの作成
        upload_dir = Path.join(["priv", "static", "uploads", "pdfs"])
        File.mkdir_p!(upload_dir)

        # ファイル名にタイムスタンプを付与して衝突を防止
        timestamp = System.system_time(:second)
        ext = Path.extname(entry.client_name)
        base = Path.basename(entry.client_name, ext)
        versioned_name = "#{base}-#{timestamp}#{ext}"
        dest = Path.join(upload_dir, versioned_name)
        File.cp!(path, dest)
        {:ok, dest}
      end)

    case uploaded_files do
      [pdf_path] ->
        # PDFソースレコードを作成
        {:ok, pdf_source} =
          Ingestion.create_pdf_source(%{
            filename: Path.basename(pdf_path),
            status: "converting",
            user_id: socket.assigns.current_user.id
          })

        # パイプラインIDを生成
        pipeline_id = Pipeline.generate_pipeline_id()

        # 非同期で並列パイプラインを開始（owner_id を伝搬）
        owner_id = socket.assigns.current_user.id

        Task.start(fn ->
          Pipeline.run_pdf_extraction(pdf_source, pdf_path, pipeline_id, %{owner_id: owner_id})
        end)

        # PipelineLive に遷移して進捗を表示
        {:noreply,
         socket
         |> assign(:uploading, false)
         |> put_flash(:info, "PDF変換パイプラインを開始しました！")
         |> push_navigate(to: ~p"/lab/pipeline/#{pipeline_id}")}

      _ ->
        {:noreply,
         socket
         |> assign(:uploading, false)
         |> assign(:error_message, "PDFファイルを選択してください")}
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
          <h2 class="section-title">PDFファイルをアップロード</h2>
          <p class="section-description">PDFファイルを選択してください。</p>

          <form id="upload-form" phx-submit="upload_pdf" phx-change="validate">
            <div class="upload-dropzone" phx-drop-target={@uploads.pdf.ref}>
              <.live_file_input upload={@uploads.pdf} class="file-input" />
              <div class="dropzone-content">
                <span class="dropzone-icon">📄</span>
                <span class="dropzone-text">ここにPDFをドラッグ、またはクリックして選択</span>
              </div>
            </div>

            <%= for entry <- @uploads.pdf.entries do %>
              <div class="upload-entry">
                <span class="entry-name">{entry.client_name}</span>
                <progress value={entry.progress} max="100" class="upload-progress">
                  {entry.progress}%
                </progress>
              </div>

              <%!-- エントリ単位のアップロードエラー表示 --%>
              <%= for err <- upload_errors(@uploads.pdf, entry) do %>
                <div class="error-message" role="alert">
                  <span class="error-icon">⚠️</span>
                  {translate_upload_error(err)}
                </div>
              <% end %>
            <% end %>

            <%!-- 全体のアップロードエラー表示 --%>
            <%= for err <- upload_errors(@uploads.pdf) do %>
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
              disabled={@uploading || @uploads.pdf.entries == []}
            >
              <%= if @uploading do %>
                <span class="spinner"></span> アップロード中...
              <% else %>
                📤 アップロードして変換する
              <% end %>
            </button>
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

  # アップロードエラーを日本語に変換するヘルパー
  defp translate_upload_error(:too_large), do: "ファイルサイズが上限（500MB）を超えています。"
  defp translate_upload_error(:too_many_files), do: "アップロードできるファイルは1つだけです。"
  defp translate_upload_error(:not_accepted), do: "PDFファイルのみアップロード可能です。"
  defp translate_upload_error(err), do: "アップロードエラー: #{inspect(err)}"
end
