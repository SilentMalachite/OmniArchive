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
      Image.write_to_buffer(cropped, ".jpg")
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

  # ポリゴンクロップ: ifthenelse 白背景合成戦略
  #
  # 1. バウンディングボックスを計算し、元画像からその領域を extract_area で切り出す
  # 2. SVG マスク（白ポリゴン/黒背景）を生成し、1バンドマスクを抽出
  # 3. 白背景RGB画像を作成
  # 4. ifthenelse でマスク白部分=元画像、マスク黒部分=白背景 に合成
  # 5. ポリゴン外が純白(255,255,255)の RGB 画像を保存
  defp crop_polygon(image_path, points, output_path) do
    with {:ok, masked} <- apply_polygon_mask(image_path, points) do
      # 白背景マスキング済みRGB画像として保存（透過不要）
      Image.write_to_file(masked, output_path)
    end
  end

  # ポリゴンクロップをバイナリとして返す（ダウンロード用）
  defp crop_polygon_to_binary(image_path, points) do
    with {:ok, masked} <- apply_polygon_mask(image_path, points) do
      Image.write_to_buffer(masked, ".png")
    end
  end

  # ポリゴンマスキングのコアロジック（ifthenelse 白背景合成）
  #
  # JPEG はアルファチャンネルを持てないため、ポリゴン外を物理的に
  # 純白 [255,255,255] で塗りつぶし、3バンド RGB 画像として返す。
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
        "[ImageProcessor] Polygon crop (white mask): bbox=#{min_x},#{min_y},#{bbox_w}x#{bbox_h} points=#{length(points)}"
      )

      # 2. バウンディングボックスで矩形クロップ（メモリ節約）
      with {:ok, cropped_img} <- Operation.extract_area(image, min_x, min_y, bbox_w, bbox_h) do
        width = Image.width(cropped_img)
        height = Image.height(cropped_img)

        # 3. オフセット済みポリゴン座標で SVG マスクを生成（白ポリゴン/黒背景）
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
        {:ok, mask} = Operation.extract_band(svg_img, 0)

        # 4. 純白 RGB 背景画像を作成（black → invert で全ピクセル 255）
        {:ok, black} = Operation.black(width, height)
        {:ok, white} = Operation.invert(black)
        {:ok, white_bg} = Operation.bandjoin([white, white, white])

        # 5. クロップ画像を正確に 3バンド RGB に正規化（バンドミスマッチ防止）
        {:ok, rgb_img} = Operation.extract_band(cropped_img, 0, n: 3)

        # 6. ifthenelse 合成:
        #    マスクが白(>0)の箇所 → rgb_img（元画像）
        #    マスクが黒(0)の箇所 → white_bg（純白背景）
        {:ok, final_img} = Operation.ifthenelse(mask, rgb_img, white_bg)

        {:ok, final_img}
      end
    end
  end

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
