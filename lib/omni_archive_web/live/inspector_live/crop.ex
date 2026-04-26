defmodule OmniArchiveWeb.InspectorLive.Crop do
  @moduledoc """
  ウィザード Step 3: クロップ専用画面。
  カスタム ImageSelection Hook を使用してポリゴン（多角形）で図版の範囲を定義し、
  Nudge コントロール（上下左右）で微調整を行います。
  SVG オーバーレイで選択範囲を可視化。
  Undo 機能を搭載。ダブルクリック（ダブルタップ）で明示的に保存。

  ## Write-on-Action ポリシー
  ExtractedImage レコードは save_crop 時に初めて作成されます。
  Browse からはレコードIDを受け取らず、pdf_source_id と page_number で動作します。

  ## Phase 1 注記
  ポリゴン頂点配列（points）を受信・表示するが、
  バックエンドの vix 処理は Phase 2 で対応予定。
  """
  use OmniArchiveWeb, :live_view

  import OmniArchiveWeb.WizardComponents

  alias OmniArchive.Ingestion

  @nudge_amount 10
  @max_polygon_points 64
  @max_crop_coordinate 20_000
  @max_crop_dimension 20_000
  @max_crop_pixels 100_000_000
  @invalid_crop_message "クロップ範囲が不正です"

  @impl true
  def mount(
        %{"pdf_source_id" => pdf_source_id, "page_number" => page_number_str},
        _session,
        socket
      ) do
    case parse_page_number(page_number_str) do
      {:ok, page_number} ->
        case Ingestion.get_pdf_source(pdf_source_id, socket.assigns.current_user) do
          nil -> redirect_to_lab(socket, "指定されたPDFソースが見つかりません")
          pdf_source -> mount_crop(socket, pdf_source, page_number)
        end

      :error ->
        redirect_to_lab(socket, "指定されたページが見つかりません")
    end
  end

  defp mount_crop(socket, pdf_source, page_number) do
    # この pdf_source_id + page_number に既存レコードがあるかチェック
    existing_image = Ingestion.find_extracted_image_by_page(pdf_source.id, page_number)

    # ページ画像のパスとURLを構築
    pages_dir = Path.join(["priv", "static", "uploads", "pages", "#{pdf_source.id}"])

    page_filename =
      if File.dir?(pages_dir) do
        pages_dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".png"))
        |> Enum.sort()
        |> Enum.at(page_number - 1)
      end

    image_path = if page_filename, do: Path.join(pages_dir, page_filename), else: nil

    image_url =
      if page_filename, do: "/lab/uploads/pages/#{pdf_source.id}/#{page_filename}", else: nil

    # 既存レコードがある場合はそのクロップデータをロード
    # 矩形データとポリゴンデータの両方に対応
    {crop_rect, polygon_points} =
      case existing_image do
        %{geometry: %{"points" => points}} when is_list(points) ->
          # ポリゴンデータ
          {nil, points}

        %{geometry: %{"x" => _, "y" => _, "width" => _, "height" => _} = geo} ->
          # 旧矩形データ（後方互換性: 表示のみ、JS側で4頂点に変換）
          {geo, nil}

        _ ->
          {nil, nil}
      end

    # DB に保存済みデータがあれば :saved、なければ :idle
    initial_state = if crop_rect || polygon_points, do: :saved, else: :idle

    {:ok,
     socket
     |> assign(:page_title, "図版をクロップ")
     |> assign(:current_step, 3)
     |> assign(:pdf_source, pdf_source)
     |> assign(:page_number, page_number)
     |> assign(:extracted_image, existing_image)
     |> assign(:image_path, image_path)
     |> assign(:image_url, image_url)
     |> assign(:crop_rect, crop_rect)
     |> assign(:polygon_points, polygon_points)
     |> assign(:undo_stack, [])
     |> assign(:save_state, initial_state)}
  end

  defp parse_page_number(page_number) do
    case Integer.parse(to_string(page_number)) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> :error
    end
  end

  defp redirect_to_lab(socket, message) do
    {:ok,
     socket
     |> put_flash(:error, message)
     |> push_navigate(to: ~p"/lab")}
  end

  # JS Hook からのプレビューイベント（ポリゴン頂点配列）
  @impl true
  def handle_event("preview_crop", %{"points" => points} = _params, socket)
      when is_list(points) do
    case normalize_polygon_points(points) do
      {:ok, normalized_points} ->
        # 現在の値を Undo スタックに保存
        undo_stack = push_undo(socket.assigns.polygon_points, socket.assigns.undo_stack)

        {:noreply,
         socket
         |> assign(:polygon_points, normalized_points)
         |> assign(:crop_rect, nil)
         |> assign(:undo_stack, undo_stack)
         |> assign(:save_state, :draft)}

      {:error, message} ->
        invalid_crop(socket, message)
    end
  end

  # 旧矩形フォーマットの preview_crop（後方互換性）
  @impl true
  def handle_event("preview_crop", params, socket) when is_map_key(params, "x") do
    case normalize_crop_rect(params) do
      {:ok, crop_rect} ->
        undo_stack = push_undo(socket.assigns.crop_rect, socket.assigns.undo_stack)

        {:noreply,
         socket
         |> assign(:crop_rect, crop_rect)
         |> assign(:undo_stack, undo_stack)
         |> assign(:save_state, :draft)}

      {:error, message} ->
        invalid_crop(socket, message)
    end
  end

  # ダブルクリック/ダブルタップによる明示的保存（ポリゴン）
  @impl true
  def handle_event("save_crop", %{"points" => points} = _params, socket) when is_list(points) do
    case normalize_polygon_points(points) do
      {:ok, normalized_points} ->
        geometry = %{"points" => normalized_points}
        result = persist_crop(socket, geometry)

        case result do
          {:ok, updated_image} ->
            {:noreply,
             socket
             |> assign(:extracted_image, updated_image)
             |> assign(:polygon_points, normalized_points)
             |> assign(:crop_rect, nil)
             |> assign(:save_state, :saved)
             |> push_event("save_confirmed", %{})}

          {:error, :stale} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "他ユーザーによって更新されました。ページをリロードしてください (Data conflict detected)."
             )}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "保存に失敗しました")}
        end

      {:error, message} ->
        invalid_crop(socket, message)
    end
  end

  # 旧矩形フォーマットの save_crop（後方互換性）
  @impl true
  def handle_event("save_crop", params, socket) when is_map_key(params, "x") do
    case normalize_crop_rect(params) do
      {:ok, crop_rect} ->
        result = persist_crop(socket, crop_rect)

        case result do
          {:ok, updated_image} ->
            {:noreply,
             socket
             |> assign(:extracted_image, updated_image)
             |> assign(:crop_rect, crop_rect)
             |> assign(:save_state, :saved)
             |> push_event("save_confirmed", %{})}

          {:error, :stale} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "他ユーザーによって更新されました。ページをリロードしてください (Data conflict detected)."
             )}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "保存に失敗しました")}
        end

      {:error, message} ->
        invalid_crop(socket, message)
    end
  end

  # ポリゴンクリア
  @impl true
  def handle_event("clear_polygon", _params, socket) do
    undo_stack = push_undo(socket.assigns.polygon_points, socket.assigns.undo_stack)

    {:noreply,
     socket
     |> assign(:polygon_points, nil)
     |> assign(:crop_rect, nil)
     |> assign(:undo_stack, undo_stack)
     |> assign(:save_state, :idle)
     |> push_event("clear_polygon", %{})}
  end

  # 旧イベント名の後方互換性（update_crop → preview_crop として動作）
  @impl true
  def handle_event("update_crop", params, socket) do
    handle_event("preview_crop", params, socket)
  end

  # 旧イベント名の後方互換性（update_crop_data）
  @impl true
  def handle_event("update_crop_data", crop_rect, socket) do
    case normalize_crop_rect(crop_rect) do
      {:ok, crop_rect} ->
        undo_stack = push_undo(socket.assigns.crop_rect, socket.assigns.undo_stack)

        {:noreply,
         socket
         |> assign(:crop_rect, crop_rect)
         |> assign(:undo_stack, undo_stack)
         |> assign(:save_state, :draft)}

      {:error, message} ->
        invalid_crop(socket, message)
    end
  end

  @impl true
  def handle_event("nudge", %{"direction" => direction} = params, socket) do
    amount = to_int(params["amount"] || @nudge_amount)

    # 現在の値を Undo スタックに保存
    undo_data = socket.assigns.polygon_points || socket.assigns.crop_rect
    undo_stack = push_undo(undo_data, socket.assigns.undo_stack)

    {:noreply,
     socket
     |> assign(:undo_stack, undo_stack)
     |> push_event("nudge_crop", %{direction: direction, amount: amount})}
  end

  # キーボード矢印キー対応（D-Pad 物理キー互換）
  @impl true
  def handle_event("keydown", %{"key" => key}, socket) do
    direction = arrow_key_to_direction(key)

    if direction do
      undo_data = socket.assigns.polygon_points || socket.assigns.crop_rect
      undo_stack = push_undo(undo_data, socket.assigns.undo_stack)

      {:noreply,
       socket
       |> assign(:undo_stack, undo_stack)
       |> push_event("nudge_crop", %{direction: direction, amount: @nudge_amount})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("undo", _params, socket) do
    case socket.assigns.undo_stack do
      [previous | rest] ->
        # 復元データがポリゴンかどうか判定
        {crop_rect, polygon_points, restore_data} =
          cond do
            is_list(previous) ->
              {nil, previous, %{points: previous}}

            is_map(previous) && Map.has_key?(previous, "points") ->
              {nil, previous["points"], %{points: previous["points"]}}

            is_map(previous) ->
              {previous, nil, %{crop_data: previous}}

            true ->
              {nil, nil, %{}}
          end

        {:noreply,
         socket
         |> assign(:crop_rect, crop_rect)
         |> assign(:polygon_points, polygon_points)
         |> assign(:undo_stack, rest)
         |> assign(:save_state, :draft)
         |> push_event("restore_crop", restore_data)}

      [] ->
        {:noreply, put_flash(socket, :info, "元に戻す操作はありません")}
    end
  end

  @impl true
  def handle_event("proceed_to_label", _params, socket) do
    polygon_points = socket.assigns.polygon_points
    crop_rect = socket.assigns.crop_rect
    extracted_image = socket.assigns.extracted_image

    cond do
      is_nil(polygon_points) && is_nil(crop_rect) ->
        {:noreply, put_flash(socket, :error, "クロップ範囲を指定してください")}

      is_nil(extracted_image) ->
        # まだ保存されていないのでブロック
        {:noreply, put_flash(socket, :error, "先にクロップ範囲を保存してください（ダブルクリック）")}

      true ->
        # クロップデータを最終保存してラベリング画面に遷移
        with {:ok, geometry} <- geometry_from_selection(polygon_points, crop_rect) do
          case Ingestion.update_extracted_image(extracted_image, %{
                 geometry: geometry
               }) do
            {:ok, _updated_image} ->
              {:noreply, push_navigate(socket, to: ~p"/lab/label/#{extracted_image.id}")}

            {:error, :stale} ->
              {:noreply,
               put_flash(
                 socket,
                 :error,
                 "他ユーザーによって更新されました。ページをリロードしてください (Data conflict detected)."
               )}

            {:error, _changeset} ->
              {:noreply, put_flash(socket, :error, "保存に失敗しました")}
          end
        else
          {:error, message} -> invalid_crop(socket, message)
        end
    end
  end

  defp persist_crop(socket, geometry) do
    case socket.assigns.extracted_image do
      nil ->
        # 新規作成（Write-on-Action: 初めてここでレコードを作成）
        Ingestion.create_extracted_image(%{
          pdf_source_id: socket.assigns.pdf_source.id,
          page_number: socket.assigns.page_number,
          image_path: socket.assigns.image_path,
          geometry: geometry
        })

      existing ->
        old_path = existing.image_path

        result =
          Ingestion.update_extracted_image(existing, %{
            geometry: geometry,
            image_path: socket.assigns.image_path
          })

        # 旧バージョンのファイルを削除（パスが異なる場合のみ）
        if old_path && old_path != socket.assigns.image_path do
          File.rm(old_path)
        end

        result
    end
  end

  defp geometry_from_selection(polygon_points, _crop_rect) when is_list(polygon_points) do
    case normalize_polygon_points(polygon_points) do
      {:ok, points} -> {:ok, %{"points" => points}}
      {:error, message} -> {:error, message}
    end
  end

  defp geometry_from_selection(_polygon_points, crop_rect) when is_map(crop_rect) do
    normalize_crop_rect(crop_rect)
  end

  defp geometry_from_selection(_polygon_points, _crop_rect), do: {:error, @invalid_crop_message}

  defp normalize_polygon_points(points) when is_list(points) do
    with {:ok, normalized_points} <- normalize_points_with_limit(points),
         {:ok, normalized_points} <- validate_polygon_bounds(normalized_points) do
      {:ok, normalized_points}
    end
  end

  defp normalize_points_with_limit(points) do
    points
    |> Enum.reduce_while({:ok, [], 0}, fn point, {:ok, acc, count} ->
      count = count + 1

      if count > @max_polygon_points do
        {:halt, {:error, @invalid_crop_message}}
      else
        case normalize_point(point) do
          {:ok, normalized} -> {:cont, {:ok, [normalized | acc], count}}
          :error -> {:halt, {:error, @invalid_crop_message}}
        end
      end
    end)
    |> case do
      {:ok, _points, count} when count < 3 ->
        {:error, @invalid_crop_message}

      {:ok, points, _count} ->
        {:ok, Enum.reverse(points)}

      {:error, message} ->
        {:error, message}
    end
  end

  defp normalize_point(point) when is_map(point) do
    with {:ok, x} <- normalize_coordinate(point["x"] || point[:x]),
         {:ok, y} <- normalize_coordinate(point["y"] || point[:y]) do
      {:ok, %{"x" => x, "y" => y}}
    else
      :error -> :error
    end
  end

  defp normalize_point(_point), do: :error

  defp validate_polygon_bounds(points) do
    xs = Enum.map(points, & &1["x"])
    ys = Enum.map(points, & &1["y"])
    width = Enum.max(xs) - Enum.min(xs)
    height = Enum.max(ys) - Enum.min(ys)

    validate_dimensions(width, height)
    |> case do
      :ok -> {:ok, points}
      :error -> {:error, @invalid_crop_message}
    end
  end

  defp normalize_crop_rect(rect) when is_map(rect) do
    with {:ok, x} <- normalize_coordinate(rect["x"] || rect[:x]),
         {:ok, y} <- normalize_coordinate(rect["y"] || rect[:y]),
         {:ok, width} <- normalize_dimension(rect["width"] || rect[:width]),
         {:ok, height} <- normalize_dimension(rect["height"] || rect[:height]),
         :ok <- validate_dimensions(width, height) do
      {:ok, %{"x" => x, "y" => y, "width" => width, "height" => height}}
    else
      :error -> {:error, @invalid_crop_message}
    end
  end

  defp normalize_crop_rect(_rect), do: {:error, @invalid_crop_message}

  defp normalize_coordinate(value) when is_integer(value) do
    if value >= 0 and value <= @max_crop_coordinate, do: {:ok, value}, else: :error
  end

  defp normalize_coordinate(value) when is_float(value) do
    if value >= 0 and value <= @max_crop_coordinate, do: {:ok, round(value)}, else: :error
  end

  defp normalize_coordinate(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> normalize_coordinate(parsed)
      _ -> :error
    end
  end

  defp normalize_coordinate(_value), do: :error

  defp normalize_dimension(value) when is_integer(value) do
    if value > 0 and value <= @max_crop_dimension, do: {:ok, value}, else: :error
  end

  defp normalize_dimension(value) when is_float(value) do
    if value > 0 and value <= @max_crop_dimension, do: {:ok, round(value)}, else: :error
  end

  defp normalize_dimension(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> normalize_dimension(parsed)
      _ -> :error
    end
  end

  defp normalize_dimension(_value), do: :error

  defp validate_dimensions(width, height) do
    cond do
      width <= 0 or height <= 0 -> :error
      width > @max_crop_dimension or height > @max_crop_dimension -> :error
      width * height > @max_crop_pixels -> :error
      true -> :ok
    end
  end

  defp invalid_crop(socket, message) do
    {:noreply, put_flash(socket, :error, message)}
  end

  # Undo スタックにプッシュ（最大20件）
  defp push_undo(nil, stack), do: stack
  defp push_undo(current, stack), do: [current | stack] |> Enum.take(20)

  # 矢印キー → 方向文字列変換
  defp arrow_key_to_direction("ArrowUp"), do: "up"
  defp arrow_key_to_direction("ArrowDown"), do: "down"
  defp arrow_key_to_direction("ArrowLeft"), do: "left"
  defp arrow_key_to_direction("ArrowRight"), do: "right"
  defp arrow_key_to_direction(_), do: nil

  # 安全な整数変換
  defp to_int(val) when is_integer(val), do: val
  defp to_int(val) when is_float(val), do: round(val)

  defp to_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp to_int(_), do: 0

  # crop_rect からSVGオーバーレイ用の値を安全に取得（後方互換性）
  defp crop_x(nil), do: 0
  defp crop_x(%{"x" => x}), do: x
  defp crop_x(_), do: 0

  defp crop_y(nil), do: 0
  defp crop_y(%{"y" => y}), do: y
  defp crop_y(_), do: 0

  defp crop_w(nil), do: 0
  defp crop_w(%{"width" => w}), do: w
  defp crop_w(_), do: 0

  defp crop_h(nil), do: 0
  defp crop_h(%{"height" => h}), do: h
  defp crop_h(_), do: 0

  @impl true
  def render(assigns) do
    ~H"""
    <div class="inspector-container" phx-window-keydown="keydown">
      <.wizard_header current_step={@current_step} />

      <div class="crop-area">
        <h2 class="section-title">✂️ 図版の範囲を指定してください</h2>
        <p class="section-description">
          シングルクリックで頂点を追加し、ダブルクリック（または始点をクリック）で多角形を閉じます。<br />
          Enterキーでも多角形を閉じることができます。方向ボタンで全体を微調整できます。
        </p>

        <%!-- Save ステータス --%>
        <.save_state_indicator state={@save_state} />

        <%!-- 2カラムレイアウト: 画像(左) + コントロール(右) --%>
        <div class="crop-layout">
          <%!-- 左カラム: 画像 + SVG オーバーレイ --%>
          <div class="crop-main">
            <div id="cropper-container" phx-hook="ImageSelection" class="cropper-container">
              <img
                id="inspect-target"
                src={@image_url}
                alt="クロップ対象の画像"
                class="crop-image"
              />
              <%!-- 初期クロップデータ（JS に渡すための data 属性 — 旧矩形形式の後方互換性） --%>
              <span
                class="crop-init-data"
                data-crop-x={crop_x(@crop_rect)}
                data-crop-y={crop_y(@crop_rect)}
                data-crop-w={crop_w(@crop_rect)}
                data-crop-h={crop_h(@crop_rect)}
                style="display:none;"
              />
              <%!-- SVG オーバーレイ（JS Hook が制御するため phx-update="ignore"） --%>
              <div id="crop-svg-container" phx-update="ignore">
                <svg class="crop-overlay" preserveAspectRatio="none">
                  <defs>
                    <mask id="crop-dim-mask">
                      <rect class="dim-mask" fill="white" x="0" y="0" width="100%" height="100%" />
                      <%!-- ポリゴン用のカットアウト --%>
                      <polygon class="dim-cutout" fill="black" points="" />
                    </mask>
                  </defs>
                  <%!-- 半透明の暗転マスク --%>
                  <rect
                    class="dim-overlay"
                    x="0"
                    y="0"
                    width="100%"
                    height="100%"
                    fill="rgba(0,0,0,0.45)"
                    mask="url(#crop-dim-mask)"
                  />
                  <%!-- ポリゴン、頂点、ラバーバンドはJSで動的に追加 --%>
                </svg>
              </div>
              <%!-- 操作ヒント --%>
              <div class="crop-save-hint" role="status">
                🔷 クリックで頂点追加 → ダブルクリックで閉じて保存
              </div>
            </div>

            <%!-- クリア/リセットボタン --%>
            <div class="mt-3 flex gap-3">
              <button
                type="button"
                class="btn-secondary"
                phx-click="clear_polygon"
              >
                🗑️ クリア（やり直し）
              </button>
              <button
                type="button"
                class="btn-secondary"
                phx-click="undo"
              >
                ↩️ 元に戻す
              </button>
            </div>
          </div>

          <%!-- 右カラム: D-Pad コントロール (sticky サイドバー) --%>
          <div class="crop-sidebar">
            <div class="sidebar-label">D-Pad 微調整（全体移動）</div>
            <%!-- D-Pad 3×3 Grid — インラインTailwindで明示的カラー指定 --%>
            <div
              class="grid grid-cols-3 gap-3 p-6 bg-[#1A2C42]/30 rounded-lg"
              role="group"
              aria-label="クロップ範囲の微調整（矢印キーでも操作可能）"
            >
              <%!-- Row 1: [空白] [↑] [空白] --%>
              <div></div>
              <button
                type="button"
                class="flex items-center justify-center w-16 h-16 rounded-lg border-2 border-[#E6B422] bg-transparent text-[#E6B422] hover:bg-[#E6B422] hover:text-[#1A2C42] transition-colors"
                phx-click="nudge"
                phx-value-direction="up"
                phx-value-amount="10"
                aria-label="上に移動"
              >
                <.icon name="hero-chevron-up" class="w-10 h-10" />
              </button>
              <div></div>

              <%!-- Row 2: [←] [MOVE] [→] --%>
              <button
                type="button"
                class="flex items-center justify-center w-16 h-16 rounded-lg border-2 border-[#E6B422] bg-transparent text-[#E6B422] hover:bg-[#E6B422] hover:text-[#1A2C42] transition-colors"
                phx-click="nudge"
                phx-value-direction="left"
                phx-value-amount="10"
                aria-label="左に移動"
              >
                <.icon name="hero-chevron-left" class="w-10 h-10" />
              </button>
              <div class="flex items-center justify-center text-[#E6B422] font-bold">MOVE</div>
              <button
                type="button"
                class="flex items-center justify-center w-16 h-16 rounded-lg border-2 border-[#E6B422] bg-transparent text-[#E6B422] hover:bg-[#E6B422] hover:text-[#1A2C42] transition-colors"
                phx-click="nudge"
                phx-value-direction="right"
                phx-value-amount="10"
                aria-label="右に移動"
              >
                <.icon name="hero-chevron-right" class="w-10 h-10" />
              </button>

              <%!-- Row 3: [空白] [↓] [空白] --%>
              <div></div>
              <button
                type="button"
                class="flex items-center justify-center w-16 h-16 rounded-lg border-2 border-[#E6B422] bg-transparent text-[#E6B422] hover:bg-[#E6B422] hover:text-[#1A2C42] transition-colors"
                phx-click="nudge"
                phx-value-direction="down"
                phx-value-amount="10"
                aria-label="下に移動"
              >
                <.icon name="hero-chevron-down" class="w-10 h-10" />
              </button>
              <div></div>
            </div>
          </div>
        </div>

        <div class="action-bar">
          <.link
            navigate={~p"/lab/browse/#{@pdf_source.id}"}
            class="btn-secondary btn-large"
          >
            ← 戻る
          </.link>

          <button
            type="button"
            class="btn-primary btn-large"
            phx-click="proceed_to_label"
          >
            次へ: ラベリング →
          </button>
        </div>
      </div>
    </div>
    """
  end
end
