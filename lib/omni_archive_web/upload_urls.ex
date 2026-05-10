defmodule OmniArchiveWeb.UploadUrls do
  @moduledoc """
  Builds authenticated URLs for files stored under priv/static/uploads.
  """

  alias OmniArchive.Ingestion.PdfSource
  alias OmniArchive.Repo

  @pages_prefix "priv/static/uploads/pages/"

  def page_image_url(nil), do: nil
  def page_image_url(""), do: nil

  def page_image_url(@pages_prefix <> rest) do
    case String.split(rest, "/", parts: 2) do
      [pages_dir_key, filename] when pages_dir_key != "" and filename != "" ->
        "/lab/uploads/pages/#{route_source_id(pages_dir_key)}/#{filename}"

      _ ->
        nil
    end
  end

  def page_image_url(_path), do: nil

  defp route_source_id(pages_dir_key) do
    case Integer.parse(pages_dir_key) do
      {_id, ""} ->
        pages_dir_key

      _ ->
        case Repo.get_by(PdfSource, storage_key: pages_dir_key) do
          %PdfSource{id: id} -> to_string(id)
          nil -> pages_dir_key
        end
    end
  end
end
