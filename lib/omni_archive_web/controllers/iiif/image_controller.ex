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

  alias OmniArchive.IIIF.Manifest
  alias OmniArchive.Ingestion.ImageProcessor
  alias OmniArchive.Repo

  import Ecto.Query

  @cache_dir "priv/static/iiif_cache"

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
    # quality.format を分離
    {quality, format} = parse_quality_format(quality_with_format)

    # Manifest からPTIFパスを取得
    case get_ptif_path(identifier) do
      {:ok, ptif_path} ->
        # キャッシュキーを生成
        cache_key = "#{identifier}_#{region_str}_#{size_str}_#{rotation_str}_#{quality}.#{format}"
        cache_path = Path.join(@cache_dir, cache_key)

        # キャッシュが存在すればそれを返す
        if File.exists?(cache_path) do
          send_cached_file(conn, cache_path, format)
        else
          # パラメータをパース
          region = parse_region(region_str)
          size = parse_size(size_str)
          rotation = parse_rotation(rotation_str)

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

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "指定された識別子の画像が見つかりません"})
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
    case Repo.one(from m in Manifest, where: m.identifier == ^identifier) do
      nil ->
        {:error, :not_found}

      manifest ->
        image = Repo.get!(OmniArchive.Ingestion.ExtractedImage, manifest.extracted_image_id)

        if image.ptif_path && File.exists?(image.ptif_path) do
          {:ok, image.ptif_path}
        else
          {:error, :not_found}
        end
    end
  end

  defp parse_quality_format(quality_format) do
    case String.split(quality_format, ".") do
      [quality, format] -> {quality, format}
      [quality] -> {quality, "jpg"}
    end
  end

  defp parse_region("full"), do: :full

  defp parse_region(region_str) do
    case String.split(region_str, ",") do
      [x, y, w, h] ->
        {String.to_integer(x), String.to_integer(y), String.to_integer(w), String.to_integer(h)}

      _ ->
        :full
    end
  end

  defp parse_size("max"), do: :max
  defp parse_size("full"), do: :max

  defp parse_size(size_str) do
    case String.split(size_str, ",") do
      [w, h] when w != "" and h != "" ->
        {String.to_integer(w), String.to_integer(h)}

      [w, ""] when w != "" ->
        {String.to_integer(w), nil}

      _ ->
        :max
    end
  end

  defp parse_rotation(rotation_str) do
    case Integer.parse(rotation_str) do
      {degrees, _} -> degrees
      :error -> 0
    end
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
