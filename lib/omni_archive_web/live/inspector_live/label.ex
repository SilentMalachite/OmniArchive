defmodule OmniArchiveWeb.InspectorLive.Label do
  @moduledoc """
  ウィザード Step 4: ラベリング（メタデータ入力）画面。
  1タスク1画面の原則に基づき、メタデータ入力のみに集中します。
  Auto-Save と Undo 機能を搭載。
  """
  use OmniArchiveWeb, :live_view

  import OmniArchiveWeb.WizardComponents

  alias OmniArchive.Ingestion
  alias OmniArchive.Ingestion.ImageProcessor

  @impl true
  def mount(%{"image_id" => image_id}, _session, socket) do
    extracted_image = Ingestion.get_extracted_image!(image_id)

    pdf_source =
      Ingestion.get_pdf_source!(extracted_image.pdf_source_id, socket.assigns.current_user)

    # 画像のURLを生成（プレビュー用）
    image_url =
      extracted_image.image_path
      |> String.replace_leading("priv/static/", "/")

    # 元画像の寸法を取得（Vix はヘッダーのみ遅延読み込み）
    {orig_w, orig_h} = read_source_dimensions(extracted_image.image_path)

    {:ok,
     socket
     |> assign(:page_title, "ラベリング")
     |> assign(:current_step, 4)
     |> assign(:extracted_image, extracted_image)
     |> assign(:pdf_source, pdf_source)
     |> assign(:image_url, image_url)
     |> assign(:orig_w, orig_w)
     |> assign(:orig_h, orig_h)
     |> assign(:geo, extracted_image.geometry)
     |> assign(:has_crop, extracted_image.geometry != nil)
     |> assign(:caption, extracted_image.caption || "")
     |> assign(:label, extracted_image.label || "")
     |> assign(:metadata_list, map_to_list(extracted_image.custom_metadata))
     |> assign(:undo_stack, [])
     |> assign(:validation_errors, %{})
     |> assign(:save_state, :idle)
     |> assign(
       :is_rejected,
       extracted_image.status == "rejected" || pdf_source.workflow_status == "returned"
     )}
  end

  # --- メタデータ更新イベント ---

  @impl true
  def handle_event("add_metadata", _, socket) do
    current_snapshot = take_snapshot(socket)
    undo_stack = [current_snapshot | socket.assigns.undo_stack] |> Enum.take(20)

    new_row = %{"id" => Ecto.UUID.generate(), "key" => "", "value" => ""}
    metadata_list = socket.assigns.metadata_list ++ [new_row]

    socket =
      socket
      |> assign(:undo_stack, undo_stack)
      |> assign(:metadata_list, metadata_list)
      |> auto_save_field("custom_metadata_list", metadata_list)

    {:noreply, socket}
  end

  @impl true
  def handle_event("remove_metadata", %{"id" => id}, socket) do
    current_snapshot = take_snapshot(socket)
    undo_stack = [current_snapshot | socket.assigns.undo_stack] |> Enum.take(20)

    filtered = Enum.reject(socket.assigns.metadata_list, &(&1["id"] == id))

    socket =
      socket
      |> assign(:undo_stack, undo_stack)
      |> assign(:metadata_list, filtered)
      |> auto_save_field("custom_metadata_list", filtered)

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "update_metadata_field",
        %{"id" => id, "field" => field, "value" => value},
        socket
      ) do
    current_snapshot = take_snapshot(socket)
    undo_stack = [current_snapshot | socket.assigns.undo_stack] |> Enum.take(20)

    updated_list =
      Enum.map(socket.assigns.metadata_list, fn row ->
        if row["id"] == id, do: Map.put(row, field, value), else: row
      end)

    socket =
      socket
      |> assign(:undo_stack, undo_stack)
      |> assign(:metadata_list, updated_list)
      |> auto_save_field("custom_metadata_list", updated_list)

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_field", %{"field" => field, "value" => value}, socket) do
    # 現在の値を Undo スタックに保存
    current_snapshot = take_snapshot(socket)
    undo_stack = [current_snapshot | socket.assigns.undo_stack] |> Enum.take(20)

    field_atom = String.to_existing_atom(field)

    socket =
      socket
      |> assign(field_atom, value)
      |> assign(:undo_stack, undo_stack)
      |> auto_save_field(field, value)

    {:noreply, socket}
  end

  @impl true
  def handle_event("undo", _params, socket) do
    case socket.assigns.undo_stack do
      [previous | rest] ->
        {:noreply,
         socket
         |> assign(:caption, previous.caption)
         |> assign(:label, previous.label)
         |> assign(:metadata_list, previous.custom_metadata_list)
         |> assign(:undo_stack, rest)
         |> auto_save_all(previous)}

      [] ->
        {:noreply, put_flash(socket, :info, "元に戻す操作はありません")}
    end
  end

  @impl true
  def handle_event("save", %{"action" => action}, socket) do
    do_save(socket, action)
  end

  @impl true
  def handle_info(:auto_save_complete, socket) do
    {:noreply, assign(socket, :save_state, :saved)}
  end

  @impl true
  def handle_info({:auto_save_complete, updated_image}, socket) do
    {:noreply,
     socket
     |> assign(:save_state, :saved)
     |> assign(:extracted_image, updated_image)}
  end

  @impl true
  def handle_info(:stale_detected, socket) do
    {:noreply,
     put_flash(socket, :error, "他ユーザーによって更新されました。ページをリロードしてください (Data conflict detected).")}
  end

  # --- プライベート関数 ---

  defp take_snapshot(socket) do
    %{
      caption: socket.assigns.caption,
      label: socket.assigns.label,
      custom_metadata_list: socket.assigns.metadata_list
    }
  end

  defp auto_save_field(socket, field, value) do
    socket = assign(socket, :save_state, :saving)
    extracted_image = socket.assigns.extracted_image
    lv_pid = self()

    Task.start(fn ->
      case Ingestion.update_extracted_image(extracted_image, %{
             String.to_existing_atom(field) => value
           }) do
        {:ok, updated} ->
          send(lv_pid, {:auto_save_complete, updated})

        {:error, :stale} ->
          send(lv_pid, :stale_detected)

        {:error, _} ->
          send(lv_pid, :auto_save_complete)
      end
    end)

    socket
  end

  defp auto_save_all(socket, snapshot) do
    socket = assign(socket, :save_state, :saving)
    extracted_image = socket.assigns.extracted_image
    lv_pid = self()

    Task.start(fn ->
      case Ingestion.update_extracted_image(extracted_image, snapshot) do
        {:ok, updated} ->
          send(lv_pid, {:auto_save_complete, updated})

        {:error, :stale} ->
          send(lv_pid, :stale_detected)

        {:error, _} ->
          send(lv_pid, :auto_save_complete)
      end
    end)

    socket
  end

  # 全メタデータを一括保存する共通関数
  defp save_metadata(socket, extra_attrs) do
    base_attrs = %{
      caption: socket.assigns.caption,
      label: socket.assigns.label,
      custom_metadata_list: socket.assigns.metadata_list
    }

    Ingestion.update_extracted_image(
      socket.assigns.extracted_image,
      Map.merge(base_attrs, extra_attrs)
    )
  end

  # 保存ロジック（重複チェック通過後に呼ばれる）
  # 全アクション（finish / continue）で status を pending_review に昇格する
  defp do_save(socket, action) do
    # geometry が nil の場合は保存をブロック
    if is_nil(socket.assigns.extracted_image.geometry) and is_nil(socket.assigns.geo) do
      {:noreply, put_flash(socket, :error, "⚠️ クロップ範囲が設定されていません。先にクロップ画面で範囲を指定してください。")}
    else
      # rejected 画像の場合は resubmit_image を使用
      save_result =
        if socket.assigns.is_rejected do
          # まずメタデータを保存
          case save_metadata(socket, %{}) do
            {:ok, _} ->
              # 再提出（rejected → pending_review + review_comment クリア）
              updated = Ingestion.get_extracted_image!(socket.assigns.extracted_image.id)
              Ingestion.resubmit_image(updated)

            error ->
              error
          end
        else
          # 通常: 全保存パスで status: "pending_review" を強制設定
          save_metadata(socket, %{status: "pending_review"})
        end

      case save_result do
        {:ok, _updated} ->
          # PTIF をバックグラウンド生成（全アクション共通）
          updated_image = Ingestion.get_extracted_image!(socket.assigns.extracted_image.id)

          Task.start(fn ->
            OmniArchive.Pipeline.generate_single_ptif(updated_image)
          end)

          {flash_msg, route} =
            if socket.assigns.is_rejected do
              # 再提出の場合は Lab ダッシュボードに戻る
              {"✅ 再提出しました！レビューをお待ちください。", ~p"/lab"}
            else
              case action do
                "continue" ->
                  {"✅ レビューに提出しました！次の図版を選択してください。",
                   ~p"/lab/browse/#{socket.assigns.extracted_image.pdf_source_id}"}

                _finish ->
                  {"✅ 提出しました！高解像度レビュー用に画像を処理中です。", ~p"/lab"}
              end
            end

          {:noreply,
           socket
           |> put_flash(:info, flash_msg)
           |> push_navigate(to: route)}

        {:error, :stale} ->
          {:noreply,
           put_flash(socket, :error, "他ユーザーによって更新されました。ページをリロードしてください (Data conflict detected).")}

        {:error, changeset} ->
          error_msg = format_changeset_errors(changeset)
          {:noreply, put_flash(socket, :error, "保存に失敗しました: #{error_msg}")}
      end
    end
  end

  # インラインバリデーション（入力時にエラーメッセージを表示）
  defp run_inline_validation(socket, field, value) do
    errors = socket.assigns.validation_errors

    errors =
      case field do
        "label" ->
          if value != "" and not Regex.match?(~r/^fig-\d+-\d+$/, value) do
            Map.put(errors, :label, "形式は 'fig-番号-番号' にしてください（例: fig-1-1）")
          else
            Map.delete(errors, :label)
          end

        _ ->
          errors
      end

    assign(socket, :validation_errors, errors)
  end

  # changeset のエラーメッセージをフォーマット
  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
    |> Enum.map(fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
    |> Enum.join("; ")
  end

  # 元画像の寸法を Vix で読み取る（ヘッダーのみ遅延読み込みなので軽量）
  defp read_source_dimensions(image_path) do
    case ImageProcessor.get_image_dimensions(image_path) do
      {:ok, %{width: w, height: h}} -> {w, h}
      _error -> {0, 0}
    end
  end

  defp map_to_list(nil), do: []
  defp map_to_list(map) when map == %{}, do: []

  defp map_to_list(map) do
    Enum.map(map, fn {k, v} ->
      %{"id" => Ecto.UUID.generate(), "key" => k, "value" => v}
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="inspector-container">
      <.wizard_header current_step={@current_step} />

      <div class="label-area">
        <h2 class="section-title">🏷️ 図版の情報を入力してください</h2>
        <p class="section-description">
          各フィールドに情報を入力してください。入力内容は自動的に保存されます。
        </p>

        <%!-- 差し戻しアラート --%>
        <%= if @is_rejected do %>
          <div class="rejection-alert">
            <div class="rejection-alert-header">
              <span class="rejection-alert-icon">⚠️</span>
              <span class="rejection-alert-title">この図版（またはプロジェクト）は差し戻されました</span>
            </div>
            <%= if @pdf_source.return_message do %>
              <div class="rejection-reason-box">
                <span class="rejection-reason-label">管理者からの全体コメント:</span>
                <span class="rejection-reason-text">{@pdf_source.return_message}</span>
              </div>
            <% end %>
            <%= if @extracted_image.review_comment do %>
              <div class="rejection-reason-box">
                <span class="rejection-reason-label">この画像へのコメント:</span>
                <span class="rejection-reason-text">{@extracted_image.review_comment}</span>
              </div>
            <% end %>
            <p class="rejection-alert-hint">修正を行い「再提出する」ボタンを押してください。</p>
          </div>
        <% end %>

        <%!-- Auto-Save ステータス --%>
        <.auto_save_indicator state={@save_state} />

        <%!-- クロッププレビュー画像 --%>
        <div class={if @has_crop, do: "label-crop-preview", else: "label-preview"}>
          <%= if @has_crop do %>
            <svg
              viewBox={"#{@geo["x"]} #{@geo["y"]} #{@geo["width"]} #{@geo["height"]}"}
              class="label-crop-svg"
              preserveAspectRatio="xMidYMid meet"
            >
              <image
                href={@image_url}
                width={@orig_w}
                height={@orig_h}
              />
            </svg>
          <% else %>
            <img src={@image_url} alt="選択した図版" class="label-preview-image" />
          <% end %>
        </div>

        <%!-- メタデータ入力フォーム --%>
        <div class="metadata-form">
          <div class="form-group">
            <label for="caption-input" class="form-label">📝 キャプション（図の説明）</label>
            <input
              type="text"
              id="caption-input"
              class="form-input form-input-large"
              value={@caption}
              phx-blur="update_field"
              phx-value-field="caption"
              phx-value-value={@caption}
              placeholder="例: 第3図 土器出土状況"
              name="caption"
            />
          </div>

          <div class="form-group">
            <label for="label-input" class="form-label">🏷️ ラベル（短い識別名）</label>
            <input
              type="text"
              id="label-input"
              class="form-input form-input-large"
              value={@label}
              phx-blur="update_field"
              phx-value-field="label"
              phx-value-value={@label}
              placeholder="例: fig-1-1"
              name="label"
            />

            <%!-- ラベル形式エラー --%>
            <%= if @validation_errors[:label] do %>
              <p class="field-error-text">⚠️ {@validation_errors[:label]}</p>
            <% end %>
          </div>

          <div class="metadata-custom-section" style="margin-top: 2rem;">
            <div class="flex items-center justify-between" style="margin-bottom: 1rem;">
              <label class="form-label" style="margin-bottom: 0;">➕ 動的メタデータ (カスタム属性)</label>
              <button
                type="button"
                phx-click="add_metadata"
                class="btn-secondary"
                style="padding: 0.25rem 0.5rem; font-size: 0.875rem;"
                aria-label="カスタムフィールドを追加"
              >
                + フィールドを追加
              </button>
            </div>

            <div class="space-y-3" style="display: flex; flex-direction: column; gap: 0.75rem;">
              <%= if Enum.empty?(@metadata_list) do %>
                <p style="font-size: 0.875rem; color: #9ca3af; font-style: italic;">
                  追加の属性がある場合は「フィールドを追加」を押してください。
                </p>
              <% else %>
                <div
                  :for={meta <- @metadata_list}
                  class="flex gap-2 items-start"
                  style="display: flex; gap: 0.5rem; align-items: flex-start;"
                >
                  <div style="flex: 1;">
                    <input
                      type="text"
                      value={meta["key"]}
                      phx-blur="update_metadata_field"
                      phx-value-id={meta["id"]}
                      phx-value-field="key"
                      placeholder="属性名 (例: 撮影者)"
                      class="form-input form-input-large"
                      style="width: 100%;"
                    />
                  </div>
                  <div style="flex: 2; display: flex; gap: 0.5rem;">
                    <input
                      type="text"
                      value={meta["value"]}
                      phx-blur="update_metadata_field"
                      phx-value-id={meta["id"]}
                      phx-value-field="value"
                      placeholder="値"
                      class="form-input form-input-large"
                      style="flex-grow: 1;"
                    />
                    <button
                      type="button"
                      phx-click="remove_metadata"
                      phx-value-id={meta["id"]}
                      style="padding: 0.5rem; color: #ef4444; border-radius: 0.25rem; transition: background-color 0.2s;"
                      onmouseover="this.style.backgroundColor='#fef2f2'"
                      onmouseout="this.style.backgroundColor='transparent'"
                      aria-label="削除"
                    >
                      🗑️
                    </button>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <%!-- Undo ボタン --%>
        <div class="undo-bar">
          <button
            type="button"
            class="btn-undo"
            phx-click="undo"
            disabled={@undo_stack == []}
            aria-label="元に戻す"
          >
            ↩️ 元に戻す
            <%= if @undo_stack != [] do %>
              <span class="undo-count">({length(@undo_stack)})</span>
            <% end %>
          </button>
        </div>

        <div class="action-bar-split">
          <.link
            navigate={~p"/lab/crop/#{@extracted_image.pdf_source_id}/#{@extracted_image.page_number}"}
            class="btn-secondary btn-large"
          >
            ← 戻る
          </.link>

          <div class="action-buttons">
            <%= if @is_rejected do %>
              <%!-- 再提出モード: 1つのボタンのみ --%>
              <button
                type="button"
                class="btn-resubmit btn-large"
                phx-click="save"
                phx-value-action="finish"
                aria-label="再提出する"
              >
                <span class="btn-icon">🔄</span>
                <span>再提出する</span>
              </button>
            <% else %>
              <button
                type="button"
                class="btn-save-continue"
                phx-click="save"
                phx-value-action="continue"
                aria-label="保存して次の図版へ"
              >
                <span class="btn-icon">🔄</span>
                <span>保存して次の図版へ</span>
              </button>

              <button
                type="button"
                class="btn-save-finish"
                phx-click="save"
                phx-value-action="finish"
                aria-label="保存して終了"
              >
                <span class="btn-icon">✅</span>
                <span>保存して終了</span>
              </button>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
