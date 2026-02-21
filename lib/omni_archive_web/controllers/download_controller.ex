defmodule OmniArchiveWeb.DownloadController do
  @moduledoc """
  高解像度クロップ画像のダウンロードを提供するコントローラー。
  公開済み (published) の ExtractedImage に対して、サーバーサイドで
  Vix を使ってクロップし、日本語セマンティックファイル名で配信します。
  """
  use OmniArchiveWeb, :controller

  alias OmniArchive.Ingestion.ExtractedImage
  alias OmniArchive.Ingestion.ImageProcessor
  alias OmniArchive.Repo

  @doc """
  GET /download/:id — クロップ済み画像をダウンロードとして送信します。
  """
  def show(conn, %{"id" => id}) do
    case Repo.get(ExtractedImage, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> text("画像が見つかりません")

      %ExtractedImage{status: status} when status != "published" ->
        conn
        |> put_status(:forbidden)
        |> text("この画像はダウンロードできません")

      image ->
        serve_cropped_image(conn, image)
    end
  end

  # --- プライベート関数 ---

  # クロップ済み画像をバイナリとして生成し、ダウンロードとして送信
  defp serve_cropped_image(conn, image) do
    case crop_image_to_binary(image) do
      {:ok, binary} ->
        filename = build_filename(image)

        send_download(conn, {:binary, binary},
          filename: filename,
          content_type: "image/jpeg"
        )

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> text("画像の処理に失敗しました: #{inspect(reason)}")
    end
  end

  # 画像をクロップしてバイナリに変換
  defp crop_image_to_binary(%ExtractedImage{image_path: image_path, geometry: geometry})
       when is_map(geometry) do
    ImageProcessor.crop_to_binary(image_path, geometry)
  end

  # geometry がない場合は元画像をそのまま JPEG バッファとして返す
  defp crop_image_to_binary(%ExtractedImage{image_path: image_path}) do
    with {:ok, image} <- Vix.Vips.Image.new_from_file(image_path) do
      Vix.Vips.Image.write_to_buffer(image, ".jpg")
    end
  end

  # セマンティックファイル名の生成
  # パターン: {ラベル}.jpg
  defp build_filename(image) do
    [image.label]
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.map(&sanitize_segment/1)
    |> case do
      [] -> "download.jpg"
      parts -> Enum.join(parts, "_") <> ".jpg"
    end
  end

  # 日本語対応のファイル名サニタイズ
  # - 漢字・ひらがな・カタカナは保持
  # - 半角/全角スペースを _ に置換
  # - 危険なファイルシステム文字を除去
  defp sanitize_segment(str) do
    str
    |> String.replace(~r/[\s　]+/u, "_")
    |> String.replace(~r/[\/\\:*?"<>|]/, "")
    |> String.trim("_")
  end
end
