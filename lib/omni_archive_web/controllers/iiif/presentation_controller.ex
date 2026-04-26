defmodule OmniArchiveWeb.IIIF.PresentationController do
  @moduledoc """
  IIIF Presentation API v3.0 — PdfSource 単位の Manifest コントローラー。
  エンドポイント: GET /iiif/presentation/:source_id/manifest

  PdfSource に紐づく公開済み画像を Canvas として集約した
  JSON-LD Manifest を返します。Mirador 等の IIIF ビューアで閲覧可能です。
  """
  use OmniArchiveWeb, :controller

  alias OmniArchive.Ingestion
  alias OmniArchive.Repo

  @doc """
  PdfSource 単位の IIIF 3.0 Manifest を JSON-LD で返します。

  - published ステータスの画像のみ含む
  - page_number 昇順で Canvas を生成
  """
  def manifest(conn, %{"source_id" => source_id}) do
    case Ingestion.get_pdf_source(source_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "指定された Source が見つかりません"})

      source ->
        images = Ingestion.list_published_images_by_source(source.id)
        base_url = OmniArchiveWeb.Endpoint.url()

        manifest_json = build_manifest(source, images, base_url)

        conn
        |> put_resp_content_type("application/ld+json")
        |> put_resp_header("access-control-allow-origin", "*")
        |> json(manifest_json)
    end
  end

  # --- プライベート関数 ---

  # Manifest 全体を組み立てる
  defp build_manifest(source, images, base_url) do
    manifest_id = "#{base_url}/iiif/presentation/#{source.id}/manifest"

    %{
      "@context" => "http://iiif.io/api/presentation/3/context.json",
      "id" => manifest_id,
      "type" => "Manifest",
      "label" => %{"none" => [source.filename]},
      "items" => Enum.map(images, &build_canvas(&1, base_url))
    }
  end

  # ExtractedImage → IIIF Canvas
  defp build_canvas(image, base_url) do
    {width, height} = extract_dimensions(image)
    canvas_id = "#{base_url}/iiif/presentation/#{image.pdf_source_id}/canvas/#{image.page_number}"

    %{
      "id" => canvas_id,
      "type" => "Canvas",
      "width" => width,
      "height" => height,
      "label" => %{"none" => [image.label || "Page #{image.page_number}"]},
      "items" => [
        %{
          "id" => "#{canvas_id}/page",
          "type" => "AnnotationPage",
          "items" => [
            %{
              "id" => "#{canvas_id}/page/annotation",
              "type" => "Annotation",
              "motivation" => "painting",
              "body" => build_image_body(image, base_url, width, height),
              "target" => canvas_id
            }
          ]
        }
      ]
    }
  end

  # 画像リソースの body を構築
  defp build_image_body(image, base_url, width, height) do
    image_url = build_image_url(image, base_url)

    %{
      "id" => image_url,
      "type" => "Image",
      "format" => "image/jpeg",
      "width" => width,
      "height" => height
    }
  end

  # geometry から幅・高さを抽出（フォールバック: 1000x1000）
  defp extract_dimensions(%{geometry: %{"width" => w, "height" => h}})
       when is_number(w) and is_number(h) do
    {trunc(w), trunc(h)}
  end

  defp extract_dimensions(_image), do: {1000, 1000}

  defp build_image_url(image, base_url) do
    case Repo.preload(image, :iiif_manifest).iiif_manifest do
      nil -> base_url <> "/placeholder.png"
      manifest -> "#{base_url}/iiif/image/#{manifest.identifier}/full/max/0/default.jpg"
    end
  end
end
