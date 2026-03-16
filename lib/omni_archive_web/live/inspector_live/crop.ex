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

  @impl true
  def mount(
        %{"pdf_source_id" => pdf_source_id, "page_number" => page_number_str},
        _session,
        socket
      ) do
    {page_number, _} = Integer.parse(page_number_str)
    pdf_source = Ingestion.get_pdf_source!(pdf_source_id, socket.assigns.current_user)

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
      if page_filename, do: "/uploads/pages/#{pdf_source.id}/#{page_filename}", else: nil

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

  # JS Hook からのプレビューイベント（ポリゴン頂点配列）
  @impl true
  def handle_event("preview_crop", %{"points" => points} = _params, socket)
      when is_list(points) do
    # Phase 1: ポリゴン頂点を IO.inspect で確認
    IO.inspect(points, label: "[Phase1] preview_crop polygon points")

    normalized_points = normalize_points(points)

    # 現在の値を Undo スタックに保存
    undo_stack = push_undo(socket.assigns.polygon_points, socket.assigns.undo_stack)

    {:noreply,
     socket
     |> assign(:polygon_points, normalized_points)
     |> assign(:crop_rect, nil)
     |> assign(:undo_stack, undo_stack)
     |> assign(:save_state, :draft)}
  end

  # 旧矩形フォーマットの preview_crop（後方互換性）
  @impl true
  def handle_event("preview_crop", params, socket) when is_map_key(params, "x") do
    crop_rect = %{
      "x" => to_int(params["x"]),
      "y" => to_int(params["y"]),
      "width" => to_int(params["width"]),
      "height" => to_int(params["height"])
    }

    undo_stack = push_undo(socket.assigns.crop_rect, socket.assigns.undo_stack)

    {:noreply,
     socket
     |> assign(:crop_rect, crop_rect)
     |> assign(:undo_stack, undo_stack)
     |> assign(:save_state, :draft)}
  end

  # ダブルクリック/ダブルタップによる明示的保存（ポリゴン）
  @impl true
  def handle_event("save_crop", %{"points" => points} = _params, socket) when is_list(points) do
    IO.inspect(points, label: "[Phase1] save_crop polygon points")

    normalized_points = normalize_points(points)
    geometry = %{"points" => normalized_points}

    result =
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
          # 既存レコードの更新
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
         put_flash(socket, :error, "他ユーザーによって更新されました。ページをリロードしてください (Data conflict detected).")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "保存に失敗しました")}
    end
  end

  # 旧矩形フォーマットの save_crop（後方互換性）
  @impl true
  def handle_event("save_crop", params, socket) when is_map_key(params, "x") do
    crop_rect = %{
      "x" => to_int(params["x"]),
      "y" => to_int(params["y"]),
      "width" => to_int(params["width"]),
      "height" => to_int(params["height"])
    }

    result =
      case socket.assigns.extracted_image do
        nil ->
          Ingestion.create_extracted_image(%{
            pdf_source_id: socket.assigns.pdf_source.id,
            page_number: socket.assigns.page_number,
            image_path: socket.assigns.image_path,
            geometry: crop_rect
          })

        existing ->
          old_path = existing.image_path

          result =
            Ingestion.update_extracted_image(existing, %{
              geometry: crop_rect,
              image_path: socket.assigns.image_path
            })

          if old_path && old_path != socket.assigns.image_path do
            File.rm(old_path)
          end

          result
      end

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
         put_flash(socket, :error, "他ユーザーによって更新されました。ページをリロードしてください (Data conflict detected).")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "保存に失敗しました")}
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
    undo_stack = push_undo(socket.assigns.crop_rect, socket.assigns.undo_stack)

    {:noreply,
     socket
     |> assign(:crop_rect, crop_rect)
     |> assign(:undo_stack, undo_stack)
     |> assign(:save_state, :draft)}
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
        geometry =
          if polygon_points do
            %{"points" => polygon_points}
          else
            crop_rect
          end

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
    end
  end

  # ポリゴン頂点配列の正規化（整数変換）
  defp normalize_points(points) when is_list(points) do
    Enum.map(points, fn p ->
      %{
        "x" => to_int(p["x"]),
        "y" => to_int(p["y"])
      }
    end)
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
