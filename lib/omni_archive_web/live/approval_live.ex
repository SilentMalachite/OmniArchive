defmodule OmniArchiveWeb.ApprovalLive do
  @moduledoc """
  承認ダッシュボード LiveView。
  プロジェクトリーダー向けの品質保証画面です。
  status == 'pending_review' の画像を一覧表示し、
  「承認して公開」「差し戻し」ボタンを提供します。

  認知アクセシビリティ対応:
  - 大きなボタン（最小 60x60px）
  - ステータスバッジによる視覚的な状態表示
  - シンプルなカードレイアウト
  """
  use OmniArchiveWeb, :live_view

  alias OmniArchive.Ingestion

  @impl true
  def mount(_params, _session, socket) do
    pending_images = Ingestion.list_pending_review_images()

    {:ok,
     socket
     |> assign(:page_title, "承認ダッシュボード")
     |> assign(:pending_images, pending_images)
     |> assign(:pending_count, length(pending_images))}
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    image = Ingestion.get_extracted_image!(id)

    case Ingestion.approve_and_publish(image) do
      {:ok, _updated} ->
        # リストを再取得
        pending_images = Ingestion.list_pending_review_images()

        {:noreply,
         socket
         |> assign(:pending_images, pending_images)
         |> assign(:pending_count, length(pending_images))
         |> put_flash(:info, "「#{image.label || "名称未設定"}」を公開しました！")}

      {:error, :invalid_status_transition} ->
        {:noreply, put_flash(socket, :error, "この画像は承認できません。")}
    end
  end

  @impl true
  def handle_event("reject", %{"id" => id}, socket) do
    image = Ingestion.get_extracted_image!(id)

    case Ingestion.reject_to_draft(image) do
      {:ok, _updated} ->
        # リストを再取得
        pending_images = Ingestion.list_pending_review_images()

        {:noreply,
         socket
         |> assign(:pending_images, pending_images)
         |> assign(:pending_count, length(pending_images))
         |> put_flash(:info, "「#{image.label || "名称未設定"}」を差し戻しました。")}

      {:error, :invalid_status_transition} ->
        {:noreply, put_flash(socket, :error, "この画像は差し戻しできません。")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="approval-container">
      <div class="approval-header">
        <h1 class="section-title">📋 承認ダッシュボード</h1>
        <p class="section-description">
          レビュー待ちの図版を確認し、承認または差し戻しを行います。
        </p>
        <div class="approval-stats">
          <span class="stats-badge">
            ⏳ レビュー待ち: {@pending_count} 件
          </span>
        </div>
      </div>

      <%= if @pending_images == [] do %>
        <div class="no-results">
          <span class="no-results-icon">✅</span>
          <p class="section-description">
            レビュー待ちの図版はありません。すべて処理済みです！
          </p>
        </div>
      <% else %>
        <div class="approval-grid">
          <%= for image <- @pending_images do %>
            <div class="approval-card">
              <%!-- サムネイル --%>
              <div class="approval-card-image-container">
                <img
                  src={image_thumbnail_url(image)}
                  alt={image.caption || "図版"}
                  class="approval-card-image"
                  loading="lazy"
                />
                <span class="status-badge status-pending_review">⏳ レビュー待ち</span>
              </div>

              <%!-- メタデータ --%>
              <div class="approval-card-body">
                <h3 class="approval-card-title">{image.label || "名称未設定"}</h3>
                <%= if image.caption do %>
                  <p class="approval-card-caption">{image.caption}</p>
                <% end %>
                <div class="approval-card-meta"></div>
              </div>

              <%!-- アクションボタン --%>
              <div class="approval-card-actions">
                <button
                  type="button"
                  class="btn-approve btn-large"
                  phx-click="approve"
                  phx-value-id={image.id}
                  aria-label={"「#{image.label || "名称未設定"}」を承認して公開"}
                >
                  ✅ 承認して公開
                </button>
                <button
                  type="button"
                  class="btn-reject btn-large"
                  phx-click="reject"
                  phx-value-id={image.id}
                  aria-label={"「#{image.label || "名称未設定"}」を差し戻し"}
                >
                  ↩️ 差し戻し
                </button>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>

      <div class="approval-footer">
        <.link navigate={~p"/lab"} class="btn-secondary btn-large">
          ← Lab に戻る
        </.link>
      </div>
    </div>
    """
  end

  # --- プライベート関数 ---

  # サムネイル URL の生成
  defp image_thumbnail_url(image) do
    case image.iiif_manifest do
      nil ->
        image.image_path
        |> String.replace_leading("priv/static/", "/")

      manifest ->
        "/iiif/image/#{manifest.identifier}/full/300,/0/default.jpg"
    end
  end
end
