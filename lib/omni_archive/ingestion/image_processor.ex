defmodule OmniArchive.Ingestion.ImageProcessor do
  @moduledoc """
  vix (libvips) を使用して画像処理を行うモジュール。
  クロップ、PTIF生成、タイル切り出しを担当します。

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

  @doc """
  画像をクロップして保存します。

  ## 引数
    - image_path: 元画像のパス
    - geometry: %{"x" => x, "y" => y, "width" => w, "height" => h}
    - output_path: 出力先パス
  """
  def crop_image(image_path, %{"x" => x, "y" => y, "width" => w, "height" => h}, output_path) do
    with {:ok, image} <- Image.new_from_file(image_path),
         {:ok, cropped} <- Operation.extract_area(image, round(x), round(y), round(w), round(h)) do
      Image.write_to_file(cropped, output_path)
    end
  end

  @doc """
  画像をクロップし、JPEG バイナリとして返します（ファイル保存なし）。
  ダウンロード機能で使用します。

  ## 引数
    - image_path: 元画像のパス
    - geometry: %{"x" => x, "y" => y, "width" => w, "height" => h}

  ## 戻り値
    - {:ok, binary} クロップ済み JPEG バイナリ
    - {:error, reason}
  """
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
