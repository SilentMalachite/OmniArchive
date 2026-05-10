defmodule OmniArchive.Ingestion.ImageProcessor do
  @moduledoc """
  vix (libvips) を使用して画像処理を行うモジュール。
  クロップ（矩形・ポリゴン）、PTIF生成、タイル切り出しを担当します。

  ## なぜこの設計か

  - **libvips (Vix) を採用**: ImageMagick と異なり、libvips はストリーミング処理で
    画像全体をメモリに展開しません。これにより、大容量の考古学資料画像（数十MB）
    でもメモリ使用量を低く抑えられます。BEAM VM との共存に適しています。
  - **PTIF (Pyramid TIFF)**: IIIF Image API に最適化されたフォーマットです。
    複数解像度のピラミッド構造を持つため、任意のズームレベルのタイルを
    高速に切り出せます。Deep Zoom や DZI と同等の性能を単一ファイルで実現します。
  """
  alias Vix.Vips.Image
  alias Vix.Vips.Operation

  require Logger

  # ポリゴンクロップ境界処理のチューニング
  # - boundary_samples: ポリゴン辺上から平均色を取るサンプル点数
  # - feather_radius: SVG マスクへ適用する Gaussian blur の半径（ピクセル）
  @polygon_boundary_samples 32
  @polygon_feather_radius 1.5

  @doc """
  画像をクロップして保存します。
  ポリゴンデータ（points 配列）がある場合は SVG マスク戦略で多角形クロップを実行します。
  矩形データの場合は従来の extract_area を使用します。

  ## 引数
    - image_path: 元画像のパス
    - geometry: %{"points" => [...]} または %{"x" => x, "y" => y, "width" => w, "height" => h}
    - output_path: 出力先パス
  """
  def crop_image(image_path, %{"points" => points} = _geometry, output_path)
      when is_list(points) and length(points) >= 3 do
    crop_polygon(image_path, points, output_path)
  end

  def crop_image(image_path, %{"x" => x, "y" => y, "width" => w, "height" => h}, output_path) do
    with {:ok, image} <- Image.new_from_file(image_path),
         {:ok, cropped} <- Operation.extract_area(image, round(x), round(y), round(w), round(h)) do
      Image.write_to_file(cropped, output_path)
    end
  end

  @doc """
  画像をクロップし、バイナリとして返します（ファイル保存なし）。
  ダウンロード機能で使用します。
  ポリゴンデータの場合は白背景マスキング済み画像バイナリを返します。

  ## 引数
    - image_path: 元画像のパス
    - geometry: %{"points" => [...]} または %{"x" => x, "y" => y, "width" => w, "height" => h}

  ## 戻り値
    - {:ok, binary} クロップ済み画像バイナリ
    - {:error, reason}
  """
  def crop_to_binary(image_path, %{"points" => points} = _geometry)
      when is_list(points) and length(points) >= 3 do
    crop_polygon_to_binary(image_path, points)
  end

  def crop_to_binary(image_path, %{"x" => x, "y" => y, "width" => w, "height" => h}) do
    with {:ok, image} <- Image.new_from_file(image_path),
         {:ok, cropped} <- Operation.extract_area(image, round(x), round(y), round(w), round(h)) do
      Image.write_to_buffer(cropped, ".png")
    end
  end

  @doc """
  画像からピラミッド型TIFF (PTIF) を生成します。

  ## 引数
    - image_path: 元画像のパス
    - ptif_path: 出力 PTIF のパス
  """
  def generate_ptif(image_path, ptif_path) do
    with {:ok, image} <- Image.new_from_file(image_path) do
      # PTIF形式で保存 (ピラミッド型TIFF)
      # 白背景マスキングは crop_image 時に完了済みのため、そのまま保存
      Image.write_to_file(image, ptif_path <> "[tile,pyramid,compression=jpeg]")
    end
  end

  @doc """
  PTIF から指定されたリージョン/サイズのタイルを切り出します。

  ## 引数
    - ptif_path: PTIF ファイルのパス
    - region: {x, y, w, h} または :full
    - size: {width, height} または :max
    - rotation: 回転角度 (0, 90, 180, 270)
    - quality: "default" | "color" | "gray"
    - format: "jpg" | "png" | "webp"

  ## 戻り値
    - {:ok, binary} タイル画像のバイナリ
    - {:error, reason}
  """
  def extract_tile(ptif_path, region, size, rotation, _quality, format) do
    with {:ok, image} <- Image.new_from_file(ptif_path) do
      # リージョンの適用
      image = apply_region(image, region)

      # サイズの適用
      image = apply_size(image, size)

      # 回転の適用
      image = apply_rotation(image, rotation)

      # フォーマット指定でバッファに書き出し
      suffix = format_to_suffix(format)
      Image.write_to_buffer(image, suffix)
    end
  end

  @doc """
  画像の幅と高さを取得します。
  """
  def get_image_dimensions(image_path) do
    with {:ok, image} <- Image.new_from_file(image_path) do
      {:ok, %{width: Image.width(image), height: Image.height(image)}}
    end
  end

  # --- プライベート関数 ---

  # ポリゴンクロップ: 境界色サンプリング + Gaussian feathering 戦略
  #
  # 1. バウンディングボックスを計算し、元画像からその領域を extract_area で切り出す
  # 2. ポリゴン辺上の N サンプル点から平均 RGB を算出（境界色）
  # 3. SVG マスク（白ポリゴン/黒背景）を生成 → Gaussian blur で feathering
  # 4. ifthenelse で連続マスクを使い、境界色背景と元画像をブレンド
  # 5. ポリゴン外が境界平均色でフェザリングされた RGB 画像を保存
  defp crop_polygon(image_path, points, output_path) do
    with {:ok, masked} <- apply_polygon_mask(image_path, points) do
      # PNG ロスレスで保存（透過不要、境界色マスキング済み）
      Image.write_to_file(masked, output_path)
    end
  end

  # ポリゴンクロップをバイナリとして返す（ダウンロード用）
  defp crop_polygon_to_binary(image_path, points) do
    with {:ok, masked} <- apply_polygon_mask(image_path, points) do
      Image.write_to_buffer(masked, ".png")
    end
  end

  # ポリゴンマスキングのコアロジック（境界色 + Gaussian feathering 合成）
  #
  # ポリゴン外を、境界辺上ピクセルの平均色で塗りつぶし、Gaussian blur で
  # マスクをぼかすことで色バンディング・エッジアーティファクトを軽減する。
  # 純白背景時に発生していた「白縁取り」を抑制し、ギャラリー表示や
  # ダウンロード画像の連続性を改善する。
  defp apply_polygon_mask(image_path, points) do
    with {:ok, image} <- Image.new_from_file(image_path) do
      # 1. バウンディングボックスを計算
      {min_x, min_y, bbox_w, bbox_h} = bounding_box(points)

      # 画像境界内にクランプ
      img_w = Image.width(image)
      img_h = Image.height(image)
      min_x = max(0, min(min_x, img_w - 1))
      min_y = max(0, min(min_y, img_h - 1))
      bbox_w = min(bbox_w, img_w - min_x)
      bbox_h = min(bbox_h, img_h - min_y)

      Logger.info(
        "[ImageProcessor] Polygon crop (boundary+feather): bbox=#{min_x},#{min_y},#{bbox_w}x#{bbox_h} points=#{length(points)}"
      )

      # 2. バウンディングボックスで矩形クロップ（メモリ節約）
      with {:ok, cropped_img} <- Operation.extract_area(image, min_x, min_y, bbox_w, bbox_h) do
        width = Image.width(cropped_img)
        height = Image.height(cropped_img)

        # 3. クロップ画像を 3バンド RGB に正規化（バンドミスマッチ防止）
        {:ok, rgb_img} = Operation.extract_band(cropped_img, 0, n: 3)

        # 4. ポリゴン辺上から境界平均色を算出（失敗時は純白フォールバック）
        boundary_rgb = sample_boundary_color(rgb_img, points, min_x, min_y, width, height)

        # 5. オフセット済みポリゴン座標で SVG マスク（白ポリゴン/黒背景）を生成
        offset_points =
          Enum.map(points, fn p ->
            x = round(p["x"] || p[:x] || 0) - min_x
            y = round(p["y"] || p[:y] || 0) - min_y
            "#{x},#{y}"
          end)
          |> Enum.join(" ")

        svg_mask = """
        <svg width="#{width}" height="#{height}">
          <rect width="100%" height="100%" fill="black" />
          <polygon points="#{offset_points}" fill="white" />
        </svg>
        """

        {:ok, {svg_img, _}} = Operation.svgload_buffer(svg_mask)
        # 1バンドマスクを抽出（白=255, 黒=0）
        {:ok, mask_raw} = Operation.extract_band(svg_img, 0)

        # 6. Gaussian blur でマスクをフェザリング（連続値マスクへ）
        mask = blur_mask(mask_raw)

        # 7. 境界色 RGB 背景画像を作成
        {:ok, bg_rgb} = build_boundary_background(width, height, boundary_rgb)

        # 8. ifthenelse 合成:
        #    マスク白部分(>0) → rgb_img（元画像）
        #    マスク黒部分(0)   → bg_rgb（境界色背景）
        #    中間値           → 線形ブレンド（フェザリング効果）
        {:ok, final_img} = Operation.ifthenelse(mask, rgb_img, bg_rgb, blend: true)

        {:ok, final_img}
      end
    end
  end

  # SVG マスクに Gaussian blur を適用してフェザリング。失敗時は元マスクをそのまま返す。
  defp blur_mask(mask) do
    case Operation.gaussblur(mask, @polygon_feather_radius) do
      {:ok, blurred} -> blurred
      _ -> mask
    end
  end

  # 境界平均色で塗りつぶした幅×高さの RGB 画像を作成
  defp build_boundary_background(width, height, {r, g, b}) do
    with {:ok, black} <- Operation.black(width, height),
         {:ok, r_band} <- Operation.linear(black, [1.0], [r * 1.0]),
         {:ok, g_band} <- Operation.linear(black, [1.0], [g * 1.0]),
         {:ok, b_band} <- Operation.linear(black, [1.0], [b * 1.0]),
         {:ok, rgb} <- Operation.bandjoin([r_band, g_band, b_band]) do
      # 念のため uchar (0-255) にキャスト
      Operation.cast(rgb, :VIPS_FORMAT_UCHAR)
    end
  end

  # ポリゴン辺上のサンプル点から平均 RGB を算出。
  # サンプルが取れない場合は純白 {255, 255, 255} にフォールバック。
  defp sample_boundary_color(rgb_img, points, min_x, min_y, width, height)
       when is_list(points) and length(points) >= 3 do
    samples =
      points
      |> edge_segments()
      |> Stream.flat_map(&interpolate_segment(&1, @polygon_boundary_samples))
      |> Stream.map(fn {x, y} -> {round(x) - min_x, round(y) - min_y} end)
      |> Stream.map(fn {x, y} -> {clamp(x, 0, width - 1), clamp(y, 0, height - 1)} end)
      |> Enum.uniq()
      |> Enum.take(@polygon_boundary_samples)

    rgbs =
      Enum.flat_map(samples, fn {x, y} ->
        case Operation.getpoint(rgb_img, x, y) do
          {:ok, [r, g, b | _]} -> [{r, g, b}]
          {:ok, [r, g]} -> [{r, g, g}]
          {:ok, [v]} -> [{v, v, v}]
          _ -> []
        end
      end)

    case rgbs do
      [] ->
        {255, 255, 255}

      list ->
        n = length(list)
        {sr, sg, sb} = Enum.reduce(list, {0.0, 0.0, 0.0}, fn {r, g, b}, {ar, ag, ab} ->
          {ar + r, ag + g, ab + b}
        end)
        {round(sr / n), round(sg / n), round(sb / n)}
    end
  end

  defp sample_boundary_color(_rgb_img, _points, _min_x, _min_y, _w, _h), do: {255, 255, 255}

  # 連続するポリゴン頂点ペアを `[{p1, p2}, …]` で返す（最後は最初に戻る閉路）
  defp edge_segments(points) do
    rotated = tl(points) ++ [hd(points)]
    Enum.zip(points, rotated)
  end

  # 1辺を samples_per_polygon / 辺数 個の点に等間隔で内分
  defp interpolate_segment({a, b}, total_samples) do
    n = max(div(total_samples, 8), 2)
    ax = a["x"] || a[:x] || 0
    ay = a["y"] || a[:y] || 0
    bx = b["x"] || b[:x] || 0
    by = b["y"] || b[:y] || 0

    for i <- 0..(n - 1) do
      t = i / max(n - 1, 1)
      {ax + (bx - ax) * t, ay + (by - ay) * t}
    end
  end

  defp clamp(v, lo, hi), do: v |> max(lo) |> min(hi)

  # ポリゴン頂点配列からバウンディングボックスを計算
  # 戻り値: {min_x, min_y, width, height}
  defp bounding_box(points) do
    xs = Enum.map(points, fn p -> round(p["x"] || p[:x] || 0) end)
    ys = Enum.map(points, fn p -> round(p["y"] || p[:y] || 0) end)

    min_x = Enum.min(xs)
    min_y = Enum.min(ys)
    max_x = Enum.max(xs)
    max_y = Enum.max(ys)

    {min_x, min_y, max_x - min_x, max_y - min_y}
  end

  defp apply_region(image, :full), do: image

  defp apply_region(image, {x, y, w, h}) do
    case Operation.extract_area(image, x, y, w, h) do
      {:ok, cropped} -> cropped
      _ -> image
    end
  end

  defp apply_size(image, :max), do: image

  defp apply_size(image, {width, height}) do
    case Operation.thumbnail_image(image, width, height: height) do
      {:ok, resized} -> resized
      _ -> image
    end
  end

  defp apply_rotation(image, 0), do: image

  defp apply_rotation(image, degrees) when degrees in [90, 180, 270] do
    angle =
      case degrees do
        90 -> :VIPS_ANGLE_D90
        180 -> :VIPS_ANGLE_D180
        270 -> :VIPS_ANGLE_D270
      end

    case Operation.rot(image, angle) do
      {:ok, rotated} -> rotated
      _ -> image
    end
  end

  defp apply_rotation(image, _), do: image
  defp format_to_suffix("jpg"), do: ".jpg"
  defp format_to_suffix("jpeg"), do: ".jpg"
  defp format_to_suffix("png"), do: ".png"
  defp format_to_suffix("webp"), do: ".webp"
  defp format_to_suffix(_), do: ".jpg"
end
