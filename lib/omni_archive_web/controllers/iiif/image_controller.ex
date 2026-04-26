defmodule OmniArchiveWeb.IIIF.ImageController do
  @moduledoc """
  IIIF Image API v3.0 コントローラー。
  エンドポイント: /iiif/image/:identifier/:region/:size/:rotation/:quality.:format

  PTIF ファイルから動的にタイルを生成し、キャッシュと共に返します。

  ## なぜこの設計か

  - **ファイルシステムキャッシュ**: 同じタイルリクエストが繰り返される場合
    （ビューアのズーム/パン操作）、libvips の処理を省略して直接ファイルを
    返すことで応答速度を大幅に改善します。Varnish や CDN に比べて
    運用が簡単で、単一サーバー構成に適しています。
  - **CORS ヘッダー**: IIIF ビューア（Mirador 等）はクロスオリジンで
    画像を取得するため、`access-control-allow-origin: *` が必須です。
  """
  use OmniArchiveWeb, :controller

  alias OmniArchive.Iiif.Manifest
  alias OmniArchive.Ingestion.ExtractedImage
  alias OmniArchive.Ingestion.ImageProcessor
  alias OmniArchive.Repo

  import Ecto.Query

  @cache_dir "priv/static/iiif_cache"
  @allowed_formats ~w(jpg jpeg png webp)
  @allowed_qualities ~w(default color gray)
  @allowed_rotations [0, 90, 180, 270]
  @max_output_dimension 4096
  @max_output_pixels @max_output_dimension * @max_output_dimension
  @max_region_dimension 20_000
  @max_region_pixels 100_000_000

  @doc """
  IIIF Image API v3.0 リクエストを処理します。
  """
  # セキュリティ注記: format_to_mime は固定マッピング（jpg/png/webp のみ）、
  # cache_path は @cache_dir 定数 + 内部生成キー、
  # image_data は libvips のバイナリ出力でありユーザー入力ではない。
  def show(conn, %{
        "identifier" => identifier,
        "region" => region_str,
        "size" => size_str,
        "rotation" => rotation_str,
        "quality" => quality_with_format
      }) do
    with {:ok, {quality, format}} <- parse_quality_format(quality_with_format),
         {:ok, region} <- parse_region(region_str),
         {:ok, size} <- parse_size(size_str),
         {:ok, rotation} <- parse_rotation(rotation_str),
         {:ok, ptif_path} <- get_ptif_path(identifier) do
      # キャッシュキーを生成
      cache_key = cache_key(identifier, region_str, size_str, rotation_str, quality, format)
      cache_path = Path.join(@cache_dir, cache_key)

      # キャッシュが存在すればそれを返す
      if File.exists?(cache_path) do
        send_cached_file(conn, cache_path, format)
      else
        case ImageProcessor.extract_tile(ptif_path, region, size, rotation, quality, format) do
          {:ok, image_data} ->
            # キャッシュに保存
            File.mkdir_p!(@cache_dir)
            File.write!(cache_path, image_data)

            conn
            |> put_resp_content_type(format_to_mime(format))
            |> put_resp_header("access-control-allow-origin", "*")
            |> send_resp(200, image_data)

          {:error, reason} ->
            conn
            |> put_status(:bad_request)
            |> json(%{error: "画像処理エラー: #{inspect(reason)}"})
        end
      end
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "指定された識別子の画像が見つかりません"})

      {:error, :invalid_params} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "不正な画像リクエストです"})
    end
  end

  @doc """
  IIIF Image API v3.0 info.json を返します。
  """
  def info(conn, %{"identifier" => identifier}) do
    case get_ptif_path(identifier) do
      {:ok, ptif_path} ->
        case ImageProcessor.get_image_dimensions(ptif_path) do
          {:ok, %{width: width, height: height}} ->
            info_json = %{
              "@context" => "http://iiif.io/api/image/3/context.json",
              "id" => "#{OmniArchiveWeb.Endpoint.url()}/iiif/image/#{identifier}",
              "type" => "ImageService3",
              "protocol" => "http://iiif.io/api/image",
              "width" => width,
              "height" => height,
              "profile" => "level1"
            }

            conn
            |> put_resp_content_type("application/ld+json")
            |> put_resp_header("access-control-allow-origin", "*")
            |> json(info_json)

          {:error, _reason} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "画像情報の取得に失敗しました"})
        end

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "指定された識別子の画像が見つかりません"})
    end
  end

  # --- プライベート関数 ---

  defp get_ptif_path(identifier) do
    query =
      from m in Manifest,
        join: e in ExtractedImage,
        on: e.id == m.extracted_image_id,
        where:
          m.identifier == ^identifier and e.status == "published" and
            not is_nil(e.ptif_path) and e.ptif_path != "",
        select: e.ptif_path

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      ptif_path ->
        if File.exists?(ptif_path) do
          {:ok, ptif_path}
        else
          {:error, :not_found}
        end
    end
  end

  defp parse_quality_format(quality_format) do
    case String.split(quality_format, ".") do
      [quality, format] when quality in @allowed_qualities and format in @allowed_formats ->
        {:ok, {quality, format}}

      [quality] when quality in @allowed_qualities ->
        {:ok, {quality, "jpg"}}

      _ ->
        {:error, :invalid_params}
    end
  end

  defp parse_region("full"), do: {:ok, :full}

  defp parse_region(region_str) do
    with [x, y, w, h] <- String.split(region_str, ","),
         {:ok, x} <- parse_non_negative_integer(x),
         {:ok, y} <- parse_non_negative_integer(y),
         {:ok, w} <- parse_positive_integer(w),
         {:ok, h} <- parse_positive_integer(h),
         true <- w <= @max_region_dimension and h <= @max_region_dimension,
         true <- w * h <= @max_region_pixels do
      {:ok, {x, y, w, h}}
    else
      _ -> {:error, :invalid_params}
    end
  end

  defp parse_size("max"), do: {:ok, :max}
  defp parse_size("full"), do: {:ok, :max}

  defp parse_size(size_str) do
    case String.split(size_str, ",") do
      [w, h] when w != "" and h != "" ->
        with {:ok, w} <- parse_positive_integer(w),
             {:ok, h} <- parse_positive_integer(h),
             :ok <- validate_output_size(w, h) do
          {:ok, {w, h}}
        else
          _ -> {:error, :invalid_params}
        end

      [w, ""] when w != "" ->
        with {:ok, w} <- parse_positive_integer(w),
             :ok <- validate_output_size(w, nil) do
          {:ok, {w, nil}}
        else
          _ -> {:error, :invalid_params}
        end

      _ ->
        {:error, :invalid_params}
    end
  end

  defp parse_rotation(rotation_str) do
    case Integer.parse(rotation_str) do
      {degrees, ""} when degrees in @allowed_rotations -> {:ok, degrees}
      _ -> {:error, :invalid_params}
    end
  end

  defp parse_non_negative_integer(value) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> {:ok, integer}
      _ -> {:error, :invalid_params}
    end
  end

  defp parse_positive_integer(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      _ -> {:error, :invalid_params}
    end
  end

  defp validate_output_size(width, nil) when width <= @max_output_dimension, do: :ok

  defp validate_output_size(width, height)
       when width <= @max_output_dimension and height <= @max_output_dimension and
              width * height <= @max_output_pixels,
       do: :ok

  defp validate_output_size(_width, _height), do: {:error, :invalid_params}

  defp cache_key(identifier, region, size, rotation, quality, format) do
    key =
      :crypto.hash(:sha256, [identifier, "\0", region, "\0", size, "\0", rotation, "\0", quality])
      |> Base.url_encode64(padding: false)

    "#{key}.#{format}"
  end

  defp format_to_mime("jpg"), do: "image/jpeg"
  defp format_to_mime("jpeg"), do: "image/jpeg"
  defp format_to_mime("png"), do: "image/png"
  defp format_to_mime("webp"), do: "image/webp"
  defp format_to_mime(_), do: "image/jpeg"

  defp send_cached_file(conn, path, format) do
    conn
    |> put_resp_content_type(format_to_mime(format))
    |> put_resp_header("access-control-allow-origin", "*")
    |> send_file(200, path)
  end
end
