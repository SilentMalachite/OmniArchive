defmodule OmniArchiveWeb.InspectorLive.Label do
  @moduledoc """
  ウィザード Step 4: ラベリング（メタデータ入力）画面。
  1タスク1画面の原則に基づき、メタデータ入力のみに集中します。
  Auto-Save と Undo 機能を搭載。
  """
  use OmniArchiveWeb, :live_view

  alias OmniArchive.DomainMetadataValidation
  alias OmniArchive.DomainProfiles
  alias OmniArchive.Ingestion.ExtractedImageMetadata
  import OmniArchiveWeb.WizardComponents

  alias OmniArchive.Ingestion
  alias OmniArchive.Ingestion.ImageProcessor

  @impl true
  def mount(%{"image_id" => image_id}, _session, socket) do
    case fetch_authorized_image(image_id, socket.assigns.current_user) do
      {:ok, extracted_image, pdf_source} ->
        mount_label(socket, extracted_image, pdf_source)

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "指定された画像が見つかりません")
         |> push_navigate(to: ~p"/lab")}
    end
  end

  defp mount_label(socket, extracted_image, pdf_source) do
    # 画像のURLを生成（プレビュー用）
    image_url = OmniArchiveWeb.UploadUrls.page_image_url(extracted_image.image_path)

    # 元画像の寸法を取得（Vix はヘッダーのみ遅延読み込み）
    {orig_w, orig_h} = read_source_dimensions(extracted_image.image_path)

    # ジオメトリからプレビュー用データを構築
    geo = extracted_image.geometry
    {polygon_points, bbox} = extract_preview_data(geo)

    {:ok,
     socket
     |> assign(:page_title, "ラベリング")
     |> assign(:current_step, 4)
     |> assign(:extracted_image, extracted_image)
     |> assign(:pdf_source, pdf_source)
     |> assign(:image_url, image_url)
     |> assign(:orig_w, orig_w)
     |> assign(:orig_h, orig_h)
     |> assign(:geo, geo)
     |> assign(:has_crop, geo != nil)
     |> assign(:polygon_points, polygon_points)
     |> assign(:bbox, bbox)
     |> assign(:summary, extracted_image.summary || "")
     |> assign(:label, extracted_image.label || "")
     |> assign(:metadata_fields, ExtractedImageMetadata.metadata_fields())
     |> assign(
       :metadata_values,
       normalize_metadata_values(ExtractedImageMetadata.read_map(extracted_image))
     )
     |> assign(:undo_stack, [])
     |> assign(:pre_edit_snapshot, nil)
     |> assign(:duplicate_record, check_duplicate_label(extracted_image))
     |> assign(:validation_errors, %{})
     |> assign(:save_state, :idle)
     |> assign(
       :is_rejected,
       extracted_image.status == "rejected" || pdf_source.workflow_status == "returned"
     )}
  end

  defp fetch_authorized_image(image_id, current_user) do
    with %{} = extracted_image <- Ingestion.get_extracted_image(image_id),
         %{} = pdf_source <- Ingestion.get_pdf_source(extracted_image.pdf_source_id, current_user) do
      {:ok, extracted_image, pdf_source}
    else
      _ -> :error
    end
  end

  # --- メタデータ更新イベント ---

  # phx-change: フォーム入力のリアルタイムバリデーション
  @impl true
  def handle_event("validate_metadata", params, socket) do
    # 編集開始時のスナップショットを保存（Undo 用）
    socket =
      if is_nil(socket.assigns.pre_edit_snapshot) do
        assign(socket, :pre_edit_snapshot, take_snapshot(socket))
      else
        socket
      end

    # フォームの実入力値で assigns を更新
    socket =
      socket
      |> assign(:summary, Map.get(params, "summary", socket.assigns.summary))
      |> assign(:label, Map.get(params, "label", socket.assigns.label))
      |> assign(:metadata_values, updated_metadata_values(socket, params))

    # 変更されたフィールドのバリデーション
    target = List.first(params["_target"] || [])

    socket =
      if target,
        do: run_inline_validation(socket, target, Map.get(params, target, "")),
        else: socket

    # label/duplicate scope 変更時は重複チェック
    socket =
      if target in ["label", duplicate_scope_field()] do
        assign(socket, :duplicate_record, check_duplicate_label(socket))
      else
        socket
      end

    {:noreply, socket}
  end

  # phx-blur: フィールド離脱時に自動保存（Undo スナップショット確定）
  @impl true
  def handle_event("blur_save_field", %{"field" => field}, socket) do
    # 編集前スナップショットを Undo スタックに追加
    {socket, undo_stack} =
      case socket.assigns.pre_edit_snapshot do
        nil ->
          {socket, socket.assigns.undo_stack}

        snapshot ->
          stack = [snapshot | socket.assigns.undo_stack] |> Enum.take(20)
          {assign(socket, :pre_edit_snapshot, nil), stack}
      end

    value = field_value(socket, field)

    socket =
      socket
      |> assign(:undo_stack, undo_stack)
      |> auto_save_field(field, value)

    {:noreply, socket}
  end

  # レガシー互換: テストから呼ばれる update_field イベント
  @impl true
  def handle_event("update_field", %{"field" => field, "value" => value}, socket) do
    current_snapshot = take_snapshot(socket)
    undo_stack = [current_snapshot | socket.assigns.undo_stack] |> Enum.take(20)

    socket =
      socket
      |> assign_field_value(field, value)
      |> assign(:undo_stack, undo_stack)
      |> auto_save_field(field, value)

    # インラインバリデーション
    socket = run_inline_validation(socket, field, value)

    # label/duplicate scope 変更時は重複チェック
    socket =
      if field in ["label", duplicate_scope_field()] do
        assign(socket, :duplicate_record, check_duplicate_label(socket))
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
         |> assign(:summary, previous.summary)
         |> assign(:label, previous.label)
         |> assign(:metadata_values, previous.metadata_values)
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
      {:noreply, put_flash(socket, :error, ui_text([:inspector_label, :duplicate_blocked]))}
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
  def handle_info({:auto_save_error, errors}, socket) do
    {:noreply,
     socket
     |> assign(:save_state, :idle)
     |> assign(:validation_errors, Map.merge(socket.assigns.validation_errors, errors))}
  end

  @impl true
  def handle_info(:stale_detected, socket) do
    {:noreply,
     put_flash(socket, :error, "他ユーザーによって更新されました。ページをリロードしてください (Data conflict detected).")}
  end

  # --- プライベート関数 ---

  defp take_snapshot(socket) do
    %{
      summary: socket.assigns.summary,
      label: socket.assigns.label,
      metadata: socket.assigns.metadata_values,
      metadata_values: socket.assigns.metadata_values
    }
  end

  defp auto_save_field(socket, field, value) do
    # 保存前の文字数制限チェック（非同期保存を試みる前にブロック）
    max_len = DomainMetadataValidation.max_length(field)

    if max_len && String.length(to_string(value)) > max_len do
      errors =
        Map.put(
          socket.assigns.validation_errors,
          validation_error_key(field),
          "#{max_len}文字以内で入力してください"
        )

      assign(socket, validation_errors: errors, save_state: :idle)
    else
      socket = assign(socket, :save_state, :saving)
      extracted_image = socket.assigns.extracted_image
      lv_pid = self()

      Task.start(fn ->
        case Ingestion.update_extracted_image(
               extracted_image,
               auto_save_attrs(socket, field, value)
             ) do
          {:ok, updated} ->
            send(lv_pid, {:auto_save_complete, updated})

          {:error, :stale} ->
            send(lv_pid, :stale_detected)

          {:error, %Ecto.Changeset{} = changeset} ->
            errors = extract_changeset_field_errors(changeset)
            send(lv_pid, {:auto_save_error, errors})

          {:error, _} ->
            send(lv_pid, :auto_save_complete)
        end
      end)

      socket
    end
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

        {:error, %Ecto.Changeset{} = changeset} ->
          errors = extract_changeset_field_errors(changeset)
          send(lv_pid, {:auto_save_error, errors})

        {:error, _} ->
          send(lv_pid, :auto_save_complete)
      end
    end)

    socket
  end

  # 全メタデータを一括保存する共通関数
  defp save_metadata(socket, extra_attrs) do
    base_attrs = %{
      summary: socket.assigns.summary,
      label: socket.assigns.label,
      metadata: socket.assigns.metadata_values
    }

    Ingestion.update_extracted_image(
      socket.assigns.extracted_image,
      Map.merge(base_attrs, extra_attrs)
    )
  end

  # 保存ロジック（重複チェック通過後に呼ばれる）
  # 全アクション（finish / continue）で status を pending_review に昇格する
  defp do_save(socket, action) do
    cond do
      # バリデーションエラーがある場合は保存をブロック
      socket.assigns.validation_errors != %{} ->
        {:noreply, put_flash(socket, :error, "⚠️ 入力エラーがあります。修正してから保存してください。")}

      # geometry が nil の場合は保存をブロック
      is_nil(socket.assigns.extracted_image.geometry) and is_nil(socket.assigns.geo) ->
        {:noreply, put_flash(socket, :error, "⚠️ クロップ範囲が設定されていません。先にクロップ画面で範囲を指定してください。")}

      true ->
        process_save(socket, action)
    end
  end

  defp process_save(socket, action) do
    save_result = execute_save_operation(socket)
    handle_save_result(save_result, socket, action)
  end

  defp execute_save_operation(socket) do
    if socket.assigns.is_rejected do
      case save_metadata(socket, %{}) do
        {:ok, _} ->
          updated = Ingestion.get_extracted_image!(socket.assigns.extracted_image.id)
          Ingestion.resubmit_image(updated)

        error ->
          error
      end
    else
      # 通常: 全保存パスで status: "pending_review" を強制設定
      save_metadata(socket, %{status: "pending_review"})
    end
  end

  defp handle_save_result({:ok, _updated}, socket, action) do
    # PTIF をバックグラウンド生成（全アクション共通）
    updated_image = Ingestion.get_extracted_image!(socket.assigns.extracted_image.id)

    Task.start(fn ->
      OmniArchive.Pipeline.generate_single_ptif(updated_image)
    end)

    {flash_msg, route} = determine_success_navigation(socket, action)

    {:noreply,
     socket
     |> put_flash(:info, flash_msg)
     |> push_navigate(to: route)}
  end

  defp handle_save_result({:error, :stale}, socket, _action) do
    {:noreply,
     put_flash(
       socket,
       :error,
       "他ユーザーによって更新されました。ページをリロードしてください (Data conflict detected)."
     )}
  end

  defp handle_save_result({:error, changeset}, socket, _action) do
    errors = extract_changeset_field_errors(changeset)

    {:noreply,
     socket
     |> assign(:validation_errors, Map.merge(socket.assigns.validation_errors, errors))
     |> put_flash(:error, "保存に失敗しました。入力内容を確認してください。")}
  end

  defp determine_success_navigation(socket, action) do
    if socket.assigns.is_rejected do
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
  end

  # 初期表示時の重複チェック
  defp check_duplicate_label(%{assigns: _assigns} = socket) do
    Ingestion.find_duplicate_extracted_image(socket.assigns.extracted_image, %{
      label: socket.assigns.label,
      metadata: socket.assigns.metadata_values
    })
  end

  defp check_duplicate_label(extracted_image) do
    Ingestion.find_duplicate_extracted_image(extracted_image)
  end

  # インラインバリデーション（入力時にエラーメッセージを表示）
  defp run_inline_validation(socket, field, value) do
    errors = validate_field(socket.assigns.validation_errors, field, value)
    assign(socket, :validation_errors, errors)
  end

  defp validate_field(errors, field, value) do
    case DomainMetadataValidation.validate_field(field, value) do
      nil -> Map.delete(errors, validation_error_key(field))
      error -> Map.put(errors, validation_error_key(field), error)
    end
  end

  # changeset からフィールドごとのエラーメッセージを抽出
  defp extract_changeset_field_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
    |> Enum.map(fn {field, [msg | _]} -> {field, msg} end)
    |> Map.new()
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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="inspector-container">
      <.wizard_header current_step={@current_step} />

      <div class="label-area">
        <h2 class="section-title">{ui_text([:inspector_label, :heading])}</h2>
        <p class="section-description">
          {ui_text([:inspector_label, :description])}
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
          <%= if @has_crop && @bbox do %>
            <svg
              viewBox={"#{@bbox.x} #{@bbox.y} #{@bbox.width} #{@bbox.height}"}
              class="label-crop-svg"
              preserveAspectRatio="xMidYMid meet"
            >
              <%!-- 白背景: clipPath 外の透過領域を白で塗りつぶし --%>
              <rect x={@bbox.x} y={@bbox.y} width={@bbox.width} height={@bbox.height} fill="white" />
              <%= if @polygon_points do %>
                <%!-- ポリゴンデータ: clipPath でマスク --%>
                <defs>
                  <clipPath id="polygon-clip">
                    <polygon points={@polygon_points} />
                  </clipPath>
                </defs>
                <image
                  href={@image_url}
                  width={@orig_w}
                  height={@orig_h}
                  clip-path="url(#polygon-clip)"
                />
              <% else %>
                <%!-- 旧矩形データ: クリップなし --%>
                <image
                  href={@image_url}
                  width={@orig_w}
                  height={@orig_h}
                />
              <% end %>
            </svg>
          <% else %>
            <img src={@image_url} alt="選択した図版" class="label-preview-image" />
          <% end %>
        </div>

        <%!-- メタデータ入力フォーム（phx-change でリアルタイムバリデーション） --%>
        <form phx-change="validate_metadata" class="metadata-form">
          <div class="form-group">
            <% summary_field = metadata_field(:summary) %>
            <label for="summary-input" class="form-label">{summary_field.label}</label>
            <input
              type="text"
              id="summary-input"
              class={["form-input form-input-large", @validation_errors[:summary] && "input-error"]}
              value={@summary}
              phx-blur="blur_save_field"
              phx-value-field="summary"
              placeholder={summary_field.placeholder}
              name="summary"
              maxlength="1000"
            />
            <%!-- サマリーエラー --%>
            <%= if @validation_errors[:summary] do %>
              <p class="field-error-text">⚠️ {@validation_errors[:summary]}</p>
            <% end %>
          </div>

          <div class="form-group">
            <% label_field = metadata_field(:label) %>
            <label for="label-input" class="form-label">{label_field.label}</label>
            <input
              type="text"
              id="label-input"
              class={[
                "form-input form-input-large",
                (@duplicate_record || @validation_errors[:label]) && "input-error"
              ]}
              value={@label}
              phx-blur="blur_save_field"
              phx-value-field="label"
              placeholder={label_field.placeholder}
              name="label"
              maxlength="100"
            />

            <%!-- ラベル形式エラー --%>
            <%= if @validation_errors[:label] do %>
              <p class="field-error-text">⚠️ {@validation_errors[:label]}</p>
            <% end %>

            <%!-- 重複検出警告 --%>
            <%= if @duplicate_record do %>
              <div class="duplicate-warning">
                <p class="duplicate-error-text">
                  ⚠️ {ui_text([:inspector_label, :duplicate_warning])}
                </p>
                <div class="duplicate-card">
                  <div class="duplicate-card-info">
                    <span class="duplicate-card-label">
                      {ui_text([:inspector_label, :duplicate_title])}
                    </span>
                    <span class="duplicate-card-id">
                      ID: #{@duplicate_record.id}
                    </span>
                    <span class="duplicate-card-summary">
                      {@duplicate_record.summary || "（サマリーなし）"}
                    </span>
                  </div>
                  <button
                    type="button"
                    class="btn-merge"
                    phx-click="merge_existing"
                    aria-label="既存レコードを編集"
                  >
                    {ui_text([:inspector_label, :duplicate_edit])}
                  </button>
                </div>
              </div>
            <% end %>
          </div>

          <%= for field <- @metadata_fields do %>
            <div class="form-group">
              <label for={"#{field.field}-input"} class="form-label">{field.label}</label>
              <input
                type="text"
                id={"#{field.field}-input"}
                class={[
                  "form-input form-input-large",
                  @validation_errors[field.field] && "input-error"
                ]}
                value={Map.get(@metadata_values, field_key(field.field), "")}
                phx-blur="blur_save_field"
                phx-value-field={field.field}
                placeholder={field.placeholder}
                name={field.field}
              />
              <%= if @validation_errors[field.field] do %>
                <p class="field-error-text">⚠️ {@validation_errors[field.field]}</p>
              <% end %>
            </div>
          <% end %>
        </form>

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

  defp metadata_field(field), do: DomainProfiles.metadata_field!(field)

  defp ui_text(path), do: DomainProfiles.ui_text(path)

  defp updated_metadata_values(socket, params) do
    Enum.reduce(socket.assigns.metadata_fields, socket.assigns.metadata_values, fn field, acc ->
      key = field_key(field.field)
      Map.put(acc, key, Map.get(params, key, Map.get(acc, key, "")))
    end)
  end

  defp normalize_metadata_values(values) do
    Map.new(values, fn {key, value} -> {to_string(key), value || ""} end)
  end

  defp field_value(socket, field) when field in ["summary", "label"],
    do: Map.get(socket.assigns, field_atom(field))

  defp field_value(socket, field), do: metadata_value(socket, field)

  defp assign_field_value(socket, field, value) when field in ["summary", "label"] do
    assign(socket, field_atom(field), value)
  end

  defp assign_field_value(socket, field, value) do
    assign(socket, :metadata_values, Map.put(socket.assigns.metadata_values, field, value))
  end

  defp metadata_value(socket, field),
    do: Map.get(socket.assigns.metadata_values, to_string(field), "")

  defp auto_save_attrs(_socket, field, value) when field in ["summary", "label"] do
    %{field_atom(field) => value}
  end

  defp auto_save_attrs(socket, field, value) do
    %{metadata: Map.put(socket.assigns.metadata_values, field, value)}
  end

  defp duplicate_scope_field do
    DomainMetadataValidation.duplicate_scope_field()
    |> to_string()
  end

  defp field_atom("summary"), do: :summary
  defp field_atom("label"), do: :label

  defp validation_error_key(field) do
    DomainProfiles.metadata_field!(field).field
  rescue
    ArgumentError -> field
  end

  defp field_key(field) when is_atom(field), do: Atom.to_string(field)
  defp field_key(field) when is_binary(field), do: field
  defp field_key(field), do: to_string(field)
end
