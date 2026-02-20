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
     |> assign(:site, extracted_image.site || "")
     |> assign(:period, extracted_image.period || "")
     |> assign(:artifact_type, extracted_image.artifact_type || "")
     |> assign(:undo_stack, [])
     |> assign(:duplicate_record, check_duplicate_label(extracted_image))
     |> assign(:validation_errors, %{})
     |> assign(:save_state, :idle)
     |> assign(
       :is_rejected,
       extracted_image.status == "rejected" || pdf_source.workflow_status == "returned"
     )}
  end

  # --- メタデータ更新イベント ---

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

    # インラインバリデーション
    socket = run_inline_validation(socket, field, value)

    # label または site 変更時は重複チェックを実行
    socket =
      if field in ["label", "site"] do
        site = if field == "site", do: value, else: socket.assigns.site
        label = if field == "label", do: value, else: socket.assigns.label

        duplicate =
          Ingestion.find_duplicate_label(
            site,
            label,
            socket.assigns.extracted_image.id
          )

        assign(socket, :duplicate_record, duplicate)
      else
        socket
      end

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
         |> assign(:site, previous.site)
         |> assign(:period, previous.period)
         |> assign(:artifact_type, previous.artifact_type)
         |> assign(:undo_stack, rest)
         |> auto_save_all(previous)}

      [] ->
        {:noreply, put_flash(socket, :info, "元に戻す操作はありません")}
    end
  end

  @impl true
  def handle_event("save", %{"action" => action}, socket) do
    # "finish" 時に重複ラベルがあればブロック
    if action == "finish" && socket.assigns.duplicate_record do
      {:noreply, put_flash(socket, :error, "⚠️ 重複ラベルがあります。ラベルを変更するか、既存レコードを更新してください。")}
    else
      do_save(socket, action)
    end
  end

  @impl true
  def handle_event("merge_existing", _params, socket) do
    # 重複レコードの編集画面にナビゲート
    case socket.assigns.duplicate_record do
      nil ->
        {:noreply, put_flash(socket, :info, "重複レコードはありません")}

      dup ->
        {:noreply,
         socket
         |> put_flash(:info, "既存レコード ##{dup.id} を編集します")
         |> push_navigate(to: ~p"/lab/label/#{dup.id}")}
    end
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
      site: socket.assigns.site,
      period: socket.assigns.period,
      artifact_type: socket.assigns.artifact_type
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
      site: socket.assigns.site,
      period: socket.assigns.period,
      artifact_type: socket.assigns.artifact_type
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

  # 初期表示時の重複チェック
  defp check_duplicate_label(extracted_image) do
    Ingestion.find_duplicate_label(
      extracted_image.site,
      extracted_image.label,
      extracted_image.id
    )
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

        "site" ->
          if value != "" and not String.contains?(value, ["市", "町", "村"]) do
            Map.put(errors, :site, "市町村名（市・町・村）を含めてください（例: 新潟市中野遺跡）")
          else
            Map.delete(errors, :site)
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
              class={["form-input form-input-large", @duplicate_record && "input-error"]}
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

            <%!-- 重複検出警告 --%>
            <%= if @duplicate_record do %>
              <div class="duplicate-warning">
                <p class="duplicate-error-text">
                  ⚠️ この遺跡でそのラベルは既に登録されています
                </p>
                <div class="duplicate-card">
                  <div class="duplicate-card-info">
                    <span class="duplicate-card-label">重複先:</span>
                    <span class="duplicate-card-id">
                      ID: #{@duplicate_record.id}
                    </span>
                    <span class="duplicate-card-caption">
                      {@duplicate_record.caption || "（キャプションなし）"}
                    </span>
                  </div>
                  <button
                    type="button"
                    class="btn-merge"
                    phx-click="merge_existing"
                    aria-label="既存レコードを編集"
                  >
                    📝 既存レコードを更新
                  </button>
                </div>
              </div>
            <% end %>
          </div>

          <div class="form-group">
            <label for="site-input" class="form-label">📍 遺跡名（任意）</label>
            <input
              type="text"
              id="site-input"
              class={["form-input form-input-large", @validation_errors[:site] && "input-error"]}
              value={@site}
              phx-blur="update_field"
              phx-value-field="site"
              phx-value-value={@site}
              placeholder="例: 新潟市中野遺跡"
              name="site"
            />
            <%!-- 遺跡名エラー --%>
            <%= if @validation_errors[:site] do %>
              <p class="field-error-text">⚠️ {@validation_errors[:site]}</p>
            <% end %>
          </div>

          <div class="form-group">
            <label for="period-input" class="form-label">⏳ 時代（任意）</label>
            <input
              type="text"
              id="period-input"
              class="form-input form-input-large"
              value={@period}
              phx-blur="update_field"
              phx-value-field="period"
              phx-value-value={@period}
              placeholder="例: 縄文時代"
              name="period"
            />
          </div>

          <div class="form-group">
            <label for="artifact-type-input" class="form-label">🏺 遺物種別（任意）</label>
            <input
              type="text"
              id="artifact-type-input"
              class="form-input form-input-large"
              value={@artifact_type}
              phx-blur="update_field"
              phx-value-field="artifact_type"
              phx-value-value={@artifact_type}
              placeholder="例: 土器"
              name="artifact_type"
            />
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
