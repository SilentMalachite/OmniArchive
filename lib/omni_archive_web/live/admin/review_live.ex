defmodule OmniArchiveWeb.Admin.ReviewLive do
  @moduledoc """
  Admin Review Dashboard LiveView。
  公開前の最終品質ゲートとして、status == "pending_review" の画像を
  管理者がレビューし、承認または差し戻しを行う画面です。

  ## PostgreSQL 15+ 要件（VCI 122 Optimized）

  本システムは PostgreSQL 15.0 以上を必須としています。理由は以下の通りです：

  - **JSONB 最適化**: 考古学メタデータ（遺跡名・時代・遺物種別等）を JSONB で
    格納しており、PostgreSQL 15 で導入された JSONB のパフォーマンス改善
    （重複キー排除の最適化、`jsonb_path_query` の高速化）を活用しています。
  - **MERGE ステートメント**: PostgreSQL 15 で標準 SQL 準拠の `MERGE` 文が
    サポートされ、Upsert 処理の可読性と保守性が向上しています。

  `mix review` パイプラインにてバージョン検証が自動実行されます。

  ## 機能
  - 大型カードグリッドで pending_review 画像を一覧表示
  - Nudge Inspector（サイドパネル）でフル画像を確認
  - Validation Badge で技術的妥当性を視覚的に表示
  - Optimistic UI: 承認時にカードがフェードアウトアニメーション

  ## 認知アクセシビリティ対応
  - 大きなボタン（最小 60×60px）
  - 高コントラスト色使い
  - 明確な状態遷移フィードバック
  """
  use OmniArchiveWeb, :live_view

  alias OmniArchive.Ingestion
  alias OmniArchive.Ingestion.ExtractedImageMetadata
  alias OmniArchive.Ingestion.ImageProcessor

  @impl true
  def mount(_params, _session, socket) do
    pending_images = Ingestion.list_pending_review_images()

    # 各画像にバリデーション結果を付与
    images_with_validation =
      Enum.map(pending_images, fn image ->
        validation = Ingestion.validate_image_data(image)
        %{image: image, validation: validation}
      end)

    # カード用のプレビューマップを構築（SVG viewBox + ポリゴン クロップ表示用）
    preview_map = build_preview_map(images_with_validation)

    {:ok,
     socket
     |> assign(:page_title, "Admin Review Dashboard")
     |> assign(:pending_images, images_with_validation)
     |> assign(:pending_count, length(images_with_validation))
     |> assign(:selected_image, nil)
     |> assign(:show_reject_modal, false)
     |> assign(:reject_note, "")
     |> assign(:reject_target_id, nil)
     |> assign(:fading_ids, MapSet.new())
     |> assign(:selected_image_dims, {0, 0})
     |> assign(:selected_polygon_points, nil)
     |> assign(:selected_bbox, nil)
     |> assign(:preview_map, preview_map)}
  end

  # --- イベントハンドラ ---

  @impl true
  def handle_event("select_image", %{"id" => id}, socket) do
    image_id = String.to_integer(id)

    selected =
      Enum.find(socket.assigns.pending_images, fn item ->
        item.image.id == image_id
      end)

    # 元画像の寸法を取得（SVG viewBox クロップ表示用）
    dims = read_source_dimensions(selected.image.image_path)

    # ジオメトリからポリゴン/バウンディングボックスを抽出
    {polygon_points, bbox} = extract_preview_data(selected.image.geometry)

    {:noreply,
     socket
     |> assign(:selected_image, selected)
     |> assign(:selected_image_dims, dims)
     |> assign(:selected_polygon_points, polygon_points)
     |> assign(:selected_bbox, bbox)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    image = Ingestion.get_extracted_image!(id)

    case Ingestion.soft_delete_image(image) do
      {:ok, _deleted} ->
        # リストから即座に削除
        image_id = String.to_integer(id)

        updated_images =
          Enum.reject(socket.assigns.pending_images, fn item ->
            item.image.id == image_id
          end)

        # preview_map から該当IDを削除
        updated_preview_map = Map.delete(socket.assigns.preview_map, image_id)

        {:noreply,
         socket
         |> assign(:pending_images, updated_images)
         |> assign(:pending_count, length(updated_images))
         |> assign(:preview_map, updated_preview_map)
         |> close_inspector_if_selected(image_id)
         |> put_flash(:info, "「#{image.label || "名称未設定"}」を削除しました。")}

      {:error, :invalid_status_transition} ->
        {:noreply, put_flash(socket, :error, "この画像は削除できません。")}
    end
  end

  @impl true
  def handle_event("close_inspector", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_image, nil)
     |> assign(:selected_image_dims, {0, 0})
     |> assign(:selected_polygon_points, nil)
     |> assign(:selected_bbox, nil)}
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    image = Ingestion.get_extracted_image!(id)

    case Ingestion.approve_and_publish(image) do
      {:ok, _updated} ->
        # Optimistic UI: フェードアウト対象に追加
        image_id = String.to_integer(id)
        fading_ids = MapSet.put(socket.assigns.fading_ids, image_id)

        # 500ms 後にリストから削除（アニメーション完了後）
        Process.send_after(self(), {:remove_faded, image_id}, 500)

        {:noreply,
         socket
         |> assign(:fading_ids, fading_ids)
         |> close_inspector_if_selected(image_id)
         |> put_flash(:info, "「#{image.label || "名称未設定"}」を公開しました！ 🎉")}

      {:error, {:ptiff_generation_failed, reason}} ->
        {:noreply, put_flash(socket, :error, "PTIFF 生成に失敗しました: #{inspect(reason)}")}

      {:error, :invalid_status_transition} ->
        {:noreply, put_flash(socket, :error, "この画像は承認できません。")}
    end
  end

  @impl true
  def handle_event("open_reject_modal", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:show_reject_modal, true)
     |> assign(:reject_target_id, id)
     |> assign(:reject_note, "")}
  end

  @impl true
  def handle_event("close_reject_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_reject_modal, false)
     |> assign(:reject_target_id, nil)
     |> assign(:reject_note, "")}
  end

  @impl true
  def handle_event("update_reject_note", %{"reject_note" => %{"note" => note}}, socket) do
    {:noreply, assign(socket, :reject_note, note)}
  end

  @impl true
  def handle_event("confirm_reject", _params, socket) do
    id = socket.assigns.reject_target_id
    note = socket.assigns.reject_note
    image = Ingestion.get_extracted_image!(id)

    case Ingestion.reject_to_draft_with_note(image, note) do
      {:ok, _updated} ->
        # リストを再取得
        pending_images = Ingestion.list_pending_review_images()

        images_with_validation =
          Enum.map(pending_images, fn img ->
            validation = Ingestion.validate_image_data(img)
            %{image: img, validation: validation}
          end)

        # preview_map を再構築
        preview_map = build_preview_map(images_with_validation)
        image_id = String.to_integer(id)

        {:noreply,
         socket
         |> assign(:pending_images, images_with_validation)
         |> assign(:pending_count, length(images_with_validation))
         |> assign(:preview_map, preview_map)
         |> assign(:show_reject_modal, false)
         |> assign(:reject_target_id, nil)
         |> assign(:reject_note, "")
         |> close_inspector_if_selected(image_id)
         |> put_flash(:info, "「#{image.label || "名称未設定"}」を差し戻しました。")}

      {:error, :invalid_status_transition} ->
        {:noreply,
         socket
         |> assign(:show_reject_modal, false)
         |> put_flash(:error, "この画像は差し戻しできません。")}
    end
  end

  @impl true
  def handle_info({:remove_faded, image_id}, socket) do
    # フェードアウト完了: リストから削除
    updated_images =
      Enum.reject(socket.assigns.pending_images, fn item ->
        item.image.id == image_id
      end)

    fading_ids = MapSet.delete(socket.assigns.fading_ids, image_id)
    # preview_map から該当IDを削除
    updated_preview_map = Map.delete(socket.assigns.preview_map, image_id)

    {:noreply,
     socket
     |> assign(:pending_images, updated_images)
     |> assign(:pending_count, length(updated_images))
     |> assign(:fading_ids, fading_ids)
     |> assign(:preview_map, updated_preview_map)}
  end

  # --- レンダリング ---

  @impl true
  def render(assigns) do
    ~H"""
    <div class="admin-review-container">
      <%!-- ヘッダー --%>
      <div class="admin-review-header">
        <h1 class="section-title">🛡️ Admin Review Dashboard</h1>
        <p class="section-description">
          公開前の最終品質チェックです。画像とメタデータを確認し、承認または差し戻しを行います。
        </p>
        <div class="review-stats">
          <span class="stats-badge stats-badge-pending">
            ⏳ レビュー待ち: {@pending_count} 件
          </span>
        </div>
      </div>

      <%!-- メインコンテンツ: グリッド + インスペクター --%>
      <div class={"review-layout #{if @selected_image, do: "inspector-open", else: ""}"}>
        <%!-- カードグリッド --%>
        <div class="review-grid-area">
          <%= if @pending_images == [] do %>
            <div class="no-results">
              <span class="no-results-icon">✅</span>
              <p class="section-description">
                レビュー待ちの図版はありません。すべて処理済みです！
              </p>
            </div>
          <% else %>
            <div class="review-grid columns-1 sm:columns-2 md:columns-3 lg:columns-4 gap-4 space-y-4">
              <%= for item <- @pending_images do %>
                <div
                  id={"review-card-#{item.image.id}"}
                  class={"review-card break-inside-avoid mb-4 status-pending #{if @selected_image && @selected_image.image.id == item.image.id, do: "selected", else: ""} #{if MapSet.member?(@fading_ids, item.image.id), do: "card-fade-out", else: ""}"}
                  phx-click="select_image"
                  phx-value-id={item.image.id}
                  role="button"
                  tabindex="0"
                  aria-label={"「#{item.image.label || "名称未設定"}」を選択"}
                >
                  <%!-- Validation Badge --%>
                  <div class="validation-badge-container">
                    <%= case item.validation do %>
                      <% {:ok, :valid} -> %>
                        <span class="validation-badge badge-valid" title="技術的に有効">
                          ✓ OK
                        </span>
                      <% {:error, _issues} -> %>
                        <span
                          class="validation-badge badge-warning"
                          title="確認が必要な項目があります"
                        >
                          ⚠ 要確認
                        </span>
                    <% end %>
                  </div>

                  <%!-- 画像サムネイル（SVG viewBox クロップ表示） --%>
                  <div class="review-card-image-container">
                    <%= if is_nil(item.image.ptif_path) do %>
                      <div class="review-card-processing">
                        <span class="processing-icon">⏳</span>
                        <span class="processing-text">画像処理中...</span>
                      </div>
                    <% else %>
                      <%= if item.image.geometry do %>
                        <% {orig_w, orig_h, poly_pts, card_bbox} =
                          Map.get(@preview_map, item.image.id, {0, 0, nil, nil}) %>
                        <%= if card_bbox do %>
                          <div class="relative w-full bg-[#0F1923] flex items-center justify-center rounded-t-lg overflow-hidden">
                            <svg
                              viewBox={"#{card_bbox.x} #{card_bbox.y} #{card_bbox.width} #{card_bbox.height}"}
                              class="w-full h-auto"
                              preserveAspectRatio="xMidYMid meet"
                            >
                              <%!-- 白背景: clipPath 外の透過領域を白で塗りつぶし --%>
                              <rect
                                x={card_bbox.x}
                                y={card_bbox.y}
                                width={card_bbox.width}
                                height={card_bbox.height}
                                fill="white"
                              />
                              <%= if poly_pts do %>
                                <%!-- ポリゴンデータ: clipPath でマスク --%>
                                <defs>
                                  <clipPath id={"review-card-clip-#{item.image.id}"}>
                                    <polygon points={poly_pts} />
                                  </clipPath>
                                </defs>
                                <image
                                  href={image_thumbnail_url(item.image)}
                                  width={orig_w}
                                  height={orig_h}
                                  clip-path={"url(#review-card-clip-#{item.image.id})"}
                                />
                              <% else %>
                                <%!-- 旧矩形データ: クリップなし --%>
                                <image
                                  href={image_thumbnail_url(item.image)}
                                  width={orig_w}
                                  height={orig_h}
                                />
                              <% end %>
                            </svg>
                          </div>
                        <% end %>
                      <% else %>
                        <img
                          src={image_thumbnail_url(item.image)}
                          alt={item.image.summary || "図版"}
                          class="review-card-image"
                          loading="lazy"
                          onerror="this.style.display='none';this.nextElementSibling.style.display='flex'"
                        />
                        <div class="review-card-processing" style="display:none">
                          <span class="processing-icon">🖼️</span>
                          <span class="processing-text">画像なし</span>
                        </div>
                      <% end %>
                    <% end %>
                  </div>

                  <%!-- メタデータ --%>
                  <div class="review-card-body">
                    <h3 class="review-card-title">{item.image.label || "名称未設定"}</h3>
                    <div class="review-card-meta">
                      <%= if item.image.site do %>
                        <span class="meta-tag">📍 {item.image.site}</span>
                      <% end %>
                      <%= if item.image.page_number do %>
                        <span class="meta-tag">📄 P.{item.image.page_number}</span>
                      <% end %>
                      <%= if item.image.period do %>
                        <span class="meta-tag">⏳ {item.image.period}</span>
                      <% end %>
                    </div>
                  </div>

                  <%!-- カードアクションボタン --%>
                  <div class="review-card-actions">
                    <button
                      type="button"
                      class={"btn-approve btn-large #{if is_nil(item.image.ptif_path), do: "btn-disabled", else: ""}"}
                      phx-click="approve"
                      phx-value-id={item.image.id}
                      phx-disable-with="⏳ PTIFF生成中..."
                      disabled={is_nil(item.image.ptif_path)}
                      aria-label={"「#{item.image.label || "名称未設定"}」を承認して公開"}
                    >
                      ✅ 承認
                    </button>
                    <button
                      type="button"
                      class="btn-reject btn-large"
                      phx-click="open_reject_modal"
                      phx-value-id={item.image.id}
                      aria-label={"「#{item.image.label || "名称未設定"}」を差し戻し"}
                    >
                      ↩️ 差し戻し
                    </button>
                  </div>
                  <%!-- Danger Zone: 削除ボタン --%>
                  <div class="danger-zone">
                    <button
                      type="button"
                      class="btn-delete"
                      phx-click="delete"
                      phx-value-id={item.image.id}
                      data-confirm="この図版を完全に削除しますか？この操作は元に戻せません。"
                      aria-label={"「#{item.image.label || "名称未設定"}」を削除"}
                    >
                      🗑️ 削除
                    </button>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <%!-- Nudge Inspector サイドパネル --%>
        <%= if @selected_image do %>
          <div class="review-inspector" role="complementary" aria-label="画像インスペクター">
            <div class="inspector-header">
              <h2 class="inspector-title">🔍 インスペクター</h2>
              <button
                type="button"
                class="inspector-close-btn"
                phx-click="close_inspector"
                aria-label="インスペクターを閉じる"
              >
                ✕
              </button>
            </div>

            <%!-- クロップ画像（SVG viewBox + ポリゴン clipPath）またはフル画像 --%>
            <div class="inspector-image-container">
              <%= if @selected_image.image.geometry && @selected_bbox do %>
                <% {orig_w, orig_h} = @selected_image_dims %>
                <svg
                  viewBox={"#{@selected_bbox.x} #{@selected_bbox.y} #{@selected_bbox.width} #{@selected_bbox.height}"}
                  class="inspector-crop-svg"
                  preserveAspectRatio="xMidYMid meet"
                >
                  <%!-- 白背景: clipPath 外の透過領域を白で塗りつぶし --%>
                  <rect
                    x={@selected_bbox.x}
                    y={@selected_bbox.y}
                    width={@selected_bbox.width}
                    height={@selected_bbox.height}
                    fill="white"
                  />
                  <%= if @selected_polygon_points do %>
                    <%!-- ポリゴンデータ: clipPath でマスク --%>
                    <defs>
                      <clipPath id={"review-polygon-clip-#{@selected_image.image.id}"}>
                        <polygon points={@selected_polygon_points} />
                      </clipPath>
                    </defs>
                    <image
                      href={image_full_url(@selected_image.image)}
                      width={orig_w}
                      height={orig_h}
                      clip-path={"url(#review-polygon-clip-#{@selected_image.image.id})"}
                    />
                  <% else %>
                    <%!-- 旧矩形データ: クリップなし --%>
                    <image
                      href={image_full_url(@selected_image.image)}
                      width={orig_w}
                      height={orig_h}
                    />
                  <% end %>
                </svg>
              <% else %>
                <img
                  src={image_full_url(@selected_image.image)}
                  alt={@selected_image.image.summary || "図版"}
                  class="inspector-full-image"
                />
              <% end %>
            </div>

            <%!-- 詳細メタデータ --%>
            <div class="inspector-details">
              <div class="inspector-detail-item">
                <span class="inspector-detail-label">ラベル</span>
                <span class="inspector-detail-value">{@selected_image.image.label || "—"}</span>
              </div>
              <div class="inspector-detail-item">
                <span class="inspector-detail-label">サマリー</span>
                <span class="inspector-detail-value">{@selected_image.image.summary || "—"}</span>
              </div>
              <%= for field <- metadata_display_fields() do %>
                <div class="inspector-detail-item">
                  <span class="inspector-detail-label">{field.label}</span>
                  <span class="inspector-detail-value">
                    {metadata_value(@selected_image.image, field.field) || "—"}
                  </span>
                </div>
              <% end %>
              <div class="inspector-detail-item">
                <span class="inspector-detail-label">ページ番号</span>
                <span class="inspector-detail-value">P.{@selected_image.image.page_number}</span>
              </div>
              <div class="inspector-detail-item">
                <span class="inspector-detail-label">PTIF</span>
                <span class="inspector-detail-value inspector-path">
                  {@selected_image.image.ptif_path || "—"}
                </span>
              </div>

              <%!-- Validation Badge 詳細 --%>
              <div class="inspector-validation">
                <%= case @selected_image.validation do %>
                  <% {:ok, :valid} -> %>
                    <div class="validation-detail valid">
                      <span class="validation-icon">✅</span>
                      <span>全項目OK — 画像・メタデータは技術的に有効です</span>
                    </div>
                  <% {:error, issues} -> %>
                    <div class="validation-detail warning">
                      <span class="validation-icon">⚠️</span>
                      <div>
                        <span>以下の項目を確認してください:</span>
                        <ul class="validation-issues">
                          <%= for issue <- issues do %>
                            <li>{validation_issue_label(issue)}</li>
                          <% end %>
                        </ul>
                      </div>
                    </div>
                <% end %>
              </div>
            </div>

            <%!-- インスペクターアクション --%>
            <div class="inspector-actions">
              <button
                type="button"
                class="btn-approve btn-large inspector-action-btn"
                phx-click="approve"
                phx-value-id={@selected_image.image.id}
                phx-disable-with="⏳ PTIFF生成中..."
              >
                ✅ 承認して公開
              </button>
              <button
                type="button"
                class="btn-reject btn-large inspector-action-btn"
                phx-click="open_reject_modal"
                phx-value-id={@selected_image.image.id}
              >
                ↩️ 差し戻し
              </button>
            </div>
            <%!-- Danger Zone: 削除ボタン --%>
            <div class="danger-zone inspector-danger-zone">
              <button
                type="button"
                class="btn-delete"
                phx-click="delete"
                phx-value-id={@selected_image.image.id}
                data-confirm="この図版を完全に削除しますか？この操作は元に戻せません。"
                aria-label={"「#{@selected_image.image.label || "名称未設定"}」を削除"}
              >
                🗑️ 削除
              </button>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- 差し戻しモーダル --%>
      <%= if @show_reject_modal do %>
        <div class="modal-overlay">
          <div
            class="modal-content"
            phx-click-away="close_reject_modal"
            phx-window-keydown="close_reject_modal"
            phx-key="escape"
          >
            <h3 class="modal-title">↩️ 差し戻し理由</h3>
            <p class="modal-description">
              差し戻しの理由を記入してください（任意）。
            </p>
            <form phx-change="update_reject_note" id="reject-note-form">
              <textarea
                id="reject-note-input"
                name="reject_note[note]"
                class="form-input reject-note-textarea"
                placeholder="例: メタデータに修正が必要です"
                rows="4"
              >{@reject_note}</textarea>
            </form>
            <div class="modal-actions">
              <button
                type="button"
                class="btn-secondary btn-large"
                phx-click="close_reject_modal"
              >
                キャンセル
              </button>
              <button
                type="button"
                class="btn-reject btn-large"
                phx-click="confirm_reject"
              >
                ↩️ 差し戻しを実行
              </button>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- フッターナビゲーション --%>
      <div class="admin-review-footer">
        <.link navigate={~p"/lab"} class="btn-secondary btn-large">
          ← Lab に戻る
        </.link>
        <.link navigate={~p"/gallery"} class="btn-secondary btn-large">
          🏛️ ギャラリーを確認
        </.link>
      </div>
    </div>
    """
  end

  # --- プライベート関数 ---

  defp metadata_value(image, field), do: ExtractedImageMetadata.read(image, field)
  defp metadata_display_fields, do: ExtractedImageMetadata.metadata_fields()

  # インスペクターが選択中の画像なら閉じる
  defp close_inspector_if_selected(socket, image_id) do
    if socket.assigns.selected_image &&
         socket.assigns.selected_image.image.id == image_id do
      assign(socket, :selected_image, nil)
    else
      socket
    end
  end

  # サムネイル URL の生成
  defp image_thumbnail_url(image) do
    case image.iiif_manifest do
      nil ->
        (image.image_path || "")
        |> String.replace_leading("priv/static/", "/")

      manifest ->
        "/iiif/image/#{manifest.identifier}/full/400,/0/default.jpg"
    end
  end

  # フル画像 URL の生成
  defp image_full_url(image) do
    case image.iiif_manifest do
      nil ->
        (image.image_path || "")
        |> String.replace_leading("priv/static/", "/")

      manifest ->
        "/iiif/image/#{manifest.identifier}/full/max/0/default.jpg"
    end
  end

  # 画像プレビューマップの構築（SVGカードクロップ + ポリゴン表示用）
  # 各画像IDに対し {dims_w, dims_h, polygon_points_str, bbox} を保持
  defp build_preview_map(images_with_validation) do
    Map.new(images_with_validation, fn item ->
      {orig_w, orig_h} = read_source_dimensions(item.image.image_path)
      {polygon_points, bbox} = extract_preview_data(item.image.geometry)
      {item.image.id, {orig_w, orig_h, polygon_points, bbox}}
    end)
  end

  # 元画像の寸法を Vix で読み取る（ヘッダーのみ遅延読み込みなので軽量）
  defp read_source_dimensions(image_path) do
    case ImageProcessor.get_image_dimensions(image_path) do
      {:ok, %{width: w, height: h}} -> {w, h}
      _error -> {0, 0}
    end
  end

  # ジオメトリデータからプレビュー用のポリゴン頂点とバウンディングボックスを抽出
  defp extract_preview_data(%{"points" => points}) when is_list(points) and length(points) >= 3 do
    xs = Enum.map(points, fn p -> safe_int(p["x"]) end)
    ys = Enum.map(points, fn p -> safe_int(p["y"]) end)

    min_x = Enum.min(xs)
    min_y = Enum.min(ys)
    max_x = Enum.max(xs)
    max_y = Enum.max(ys)

    bbox = %{
      x: min_x,
      y: min_y,
      width: max_x - min_x,
      height: max_y - min_y
    }

    # SVG polygon points 文字列を事前生成
    polygon_points_str =
      points
      |> Enum.map(fn p -> "#{safe_int(p["x"])},#{safe_int(p["y"])}" end)
      |> Enum.join(" ")

    {polygon_points_str, bbox}
  end

  # 旧矩形データの場合（後方互換性）
  defp extract_preview_data(%{"x" => x, "y" => y, "width" => w, "height" => h}) do
    bbox = %{x: safe_int(x), y: safe_int(y), width: safe_int(w), height: safe_int(h)}
    {nil, bbox}
  end

  defp extract_preview_data(_), do: {nil, nil}

  # 安全な整数変換
  defp safe_int(val) when is_integer(val), do: val
  defp safe_int(val) when is_float(val), do: round(val)

  defp safe_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp safe_int(_), do: 0

  # バリデーション項目のラベル
  defp validation_issue_label(:image_file), do: "画像ファイルパスが未設定です"
  defp validation_issue_label(:ptif_file), do: "PTIF ファイルパスが未設定です"
  defp validation_issue_label(:geometry), do: "クロップ座標が未設定です"
  defp validation_issue_label(:metadata), do: "ラベルが未設定です"
  defp validation_issue_label(other), do: "#{other} に問題があります"
end
