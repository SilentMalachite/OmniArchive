defmodule AlchemIiifWeb.LabLive.Show do
  @moduledoc """
  プロジェクト詳細: 選択した PdfSource に紐づく画像グリッドを表示。
  各画像のサムネイル、ステータス、ラベル情報を表示し、
  編集画面（Browse/Crop/Label）への遷移を提供します。
  画像がない場合は再処理ボタンを表示します。
  """
  use AlchemIiifWeb, :live_view

  alias AlchemIiif.Ingestion

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    current_user = socket.assigns.current_user
    pdf_source = Ingestion.get_pdf_source!(id, current_user)
    images = Ingestion.list_extracted_images(pdf_source.id)

    {:ok,
     socket
     |> assign(:page_title, pdf_source.filename)
     |> assign(:pdf_source, pdf_source)
     |> assign(:images, images)}
  end

  @impl true
  def handle_event("reprocess", _params, socket) do
    pdf_source = socket.assigns.pdf_source
    owner_id = socket.assigns.current_user.id

    case Ingestion.reprocess_pdf_source(pdf_source, %{owner_id: owner_id}) do
      {:ok, pipeline_id} ->
        {:noreply,
         socket
         |> put_flash(:info, "再処理を開始しました。パイプライン画面に遷移します。")
         |> push_navigate(to: ~p"/lab/pipeline/#{pipeline_id}")}

      {:error, :file_not_found} ->
        {:noreply, put_flash(socket, :error, "元のPDFファイルが見つかりません。再アップロードしてください。")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="lab-container">
      <div class="lab-header">
        <div class="lab-header-left">
          <.link navigate={~p"/lab"} class="btn-back">
            ← プロジェクト一覧
          </.link>
          <h1 class="lab-title">📄 {@pdf_source.filename}</h1>
        </div>
        <.link navigate={~p"/lab/browse/#{@pdf_source.id}"} class="btn-primary">
          📃 ページを見る
        </.link>
      </div>

      <div class="project-info-bar">
        <span class={"project-status-badge project-status-#{@pdf_source.status}"}>
          {status_label(@pdf_source.status)}
        </span>
        <%= if @pdf_source.page_count do %>
          <span class="meta-tag">📃 {@pdf_source.page_count} ページ</span>
        <% end %>
        <span class="meta-tag">🖼️ {length(@images)} 画像</span>
      </div>

      <%= if @images == [] do %>
        <div class="lab-empty-state">
          <span class="lab-empty-icon">🖼️</span>
          <p class="lab-empty-text">画像がありません。再抽出しますか？</p>
          <p class="lab-empty-hint">
            「ページを見る」から手動で選択するか、「再処理」で全ページを再抽出できます。
          </p>
          <div class="lab-empty-actions">
            <button
              type="button"
              class="btn-primary btn-large"
              phx-click="reprocess"
              data-confirm="PDFから画像を再抽出します。よろしいですか？"
            >
              🔄 再処理を実行
            </button>
            <.link navigate={~p"/lab/browse/#{@pdf_source.id}"} class="btn-secondary btn-large">
              📃 ページ一覧へ
            </.link>
          </div>
        </div>
      <% else %>
        <div class="image-grid">
          <%= for image <- @images do %>
            <div class="image-card" id={"image-#{image.id}"}>
              <.link navigate={image_link(image, @pdf_source)} class="image-card-link">
                <%= if image.image_path do %>
                  <div class="image-card-thumbnail">
                    <img
                      src={String.replace_leading(image.image_path, "priv/static/", "/")}
                      alt={image.label || "画像 #{image.page_number}"}
                      loading="lazy"
                    />
                  </div>
                <% else %>
                  <div class="image-card-placeholder">
                    <span>🖼️</span>
                  </div>
                <% end %>
                <div class="image-card-info">
                  <span class="image-card-label">
                    {image.label || "P.#{image.page_number}"}
                  </span>
                  <span class={"image-status-badge image-status-#{image.status}"}>
                    {image_status_label(image.status)}
                  </span>
                </div>
              </.link>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # ステータスの日本語ラベル
  defp status_label("uploading"), do: "アップロード中"
  defp status_label("converting"), do: "変換中"
  defp status_label("ready"), do: "取り込み完了"
  defp status_label("error"), do: "エラー"
  defp status_label(_), do: "不明"

  defp image_status_label("draft"), do: "下書き"
  defp image_status_label("pending_review"), do: "レビュー待ち"
  defp image_status_label("rejected"), do: "差し戻し"
  defp image_status_label("published"), do: "公開中"
  defp image_status_label(_), do: "不明"

  # 下書き（draft）の場合はクロップ画面へ、それ以外はラベリング画面へ
  defp image_link(%{status: "draft"} = image, pdf_source) do
    ~p"/lab/crop/#{pdf_source.id}/#{image.page_number}"
  end

  defp image_link(image, _pdf_source) do
    ~p"/lab/label/#{image.id}"
  end
end
