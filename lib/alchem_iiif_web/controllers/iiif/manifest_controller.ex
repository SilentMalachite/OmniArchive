defmodule AlchemIiifWeb.IIIF.ManifestController do
  @moduledoc """
  IIIF Presentation API v3.0 コントローラー。
  エンドポイント: /iiif/manifest/:identifier

  JSON-LD 形式で IIIF 3.0 準拠の Manifest を返します。
  多言語ラベル (英語/日本語) 対応。
  """
  use AlchemIiifWeb, :controller

  alias AlchemIiif.IIIF.Manifest
  alias AlchemIiif.Ingestion.{ExtractedImage, ImageProcessor}
  alias AlchemIiif.Repo

  import Ecto.Query

  @doc """
  IIIF Presentation API v3.0 Manifest を JSON-LD で返します。
  """
  def show(conn, %{"identifier" => identifier}) do
    case Repo.one(from m in Manifest, where: m.identifier == ^identifier) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Manifest が見つかりません"})

      manifest ->
        image = Repo.get!(ExtractedImage, manifest.extracted_image_id)

        # published 以外の画像は非公開
        if image.status != "published" do
          conn
          |> put_status(:forbidden)
          |> json(%{error: "この画像はまだ公開されていません"})
        else
          # 画像の寸法を取得
          dimensions =
            if image.ptif_path && File.exists?(image.ptif_path) do
              case ImageProcessor.get_image_dimensions(image.ptif_path) do
                {:ok, dims} -> dims
                _ -> %{width: 1000, height: 1000}
              end
            else
              %{width: 1000, height: 1000}
            end

          base_url = AlchemIiifWeb.Endpoint.url()

          manifest_json = %{
            "@context" => "http://iiif.io/api/presentation/3/context.json",
            "id" => "#{base_url}/iiif/manifest/#{identifier}",
            "type" => "Manifest",
            "label" => manifest.metadata["label"] || %{"none" => [identifier]},
            "summary" => manifest.metadata["summary"] || %{"none" => [""]},
            "metadata" => build_metadata(manifest.metadata),
            "items" => [
              %{
                "id" => "#{base_url}/iiif/manifest/#{identifier}/canvas/1",
                "type" => "Canvas",
                "width" => dimensions.width,
                "height" => dimensions.height,
                "label" => manifest.metadata["label"] || %{"none" => [identifier]},
                "items" => [
                  %{
                    "id" => "#{base_url}/iiif/manifest/#{identifier}/canvas/1/page/1",
                    "type" => "AnnotationPage",
                    "items" => [
                      %{
                        "id" =>
                          "#{base_url}/iiif/manifest/#{identifier}/canvas/1/page/1/annotation/1",
                        "type" => "Annotation",
                        "motivation" => "painting",
                        "body" => %{
                          "id" => "#{base_url}/iiif/image/#{identifier}/full/max/0/default.jpg",
                          "type" => "Image",
                          "format" => "image/jpeg",
                          "width" => dimensions.width,
                          "height" => dimensions.height,
                          "service" => [
                            %{
                              "id" => "#{base_url}/iiif/image/#{identifier}",
                              "type" => "ImageService3",
                              "profile" => "level1"
                            }
                          ]
                        },
                        "target" => "#{base_url}/iiif/manifest/#{identifier}/canvas/1"
                      }
                    ]
                  }
                ]
              }
            ]
          }

          conn
          |> put_resp_content_type("application/ld+json")
          |> put_resp_header(
            "access-control-allow-origin",
            "*"
          )
          |> json(manifest_json)
        end
    end
  end

  # --- プライベート関数 ---

  # メタデータを IIIF 3.0 形式に変換
  defp build_metadata(metadata) when is_map(metadata) do
    metadata
    |> Map.drop(["label", "summary"])
    |> Enum.map(fn {key, value} ->
      %{
        "label" => %{"en" => [key]},
        "value" => format_metadata_value(value)
      }
    end)
  end

  defp build_metadata(_), do: []

  defp format_metadata_value(value) when is_map(value), do: value
  defp format_metadata_value(value) when is_list(value), do: %{"none" => value}
  defp format_metadata_value(value), do: %{"none" => [to_string(value)]}
end
