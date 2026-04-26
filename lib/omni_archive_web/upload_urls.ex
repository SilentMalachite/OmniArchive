defmodule OmniArchiveWeb.UploadUrls do
  @moduledoc """
  Builds authenticated URLs for files stored under priv/static/uploads.
  """

  @pages_prefix "priv/static/uploads/pages/"

  def page_image_url(nil), do: nil
  def page_image_url(""), do: nil

  def page_image_url(@pages_prefix <> rest) do
    case String.split(rest, "/", parts: 2) do
      [pdf_source_id, filename] when pdf_source_id != "" and filename != "" ->
        "/lab/uploads/pages/#{pdf_source_id}/#{filename}"

      _ ->
        nil
    end
  end

  def page_image_url(_path), do: nil
end
