defmodule OmniArchiveWeb.UploadAssetController do
  use OmniArchiveWeb, :controller

  alias OmniArchive.Ingestion
  alias OmniArchive.Ingestion.PdfSource

  # ルート上の `:pdf_source_id` パラメータには、後方互換のため
  # 整数 ID（旧形式）が渡される。内部では PdfSource を引いて
  # storage_key ベースのページディレクトリを解決する。
  def page(conn, %{"pdf_source_id" => pdf_source_id, "filename" => filename}) do
    with true <- safe_page_filename?(filename),
         %{user: user} <- conn.assigns.current_scope,
         {:ok, pdf_source} <- fetch_pdf_source(pdf_source_id, user),
         path <- Path.join(PdfSource.pages_dir(pdf_source), filename),
         true <- File.regular?(path) do
      conn
      |> put_resp_content_type(MIME.from_path(filename))
      |> send_file(200, path)
    else
      _ -> not_found(conn)
    end
  end

  defp fetch_pdf_source(pdf_source_id, user) do
    case Ingestion.get_pdf_source(pdf_source_id, user) do
      nil -> :error
      pdf_source -> {:ok, pdf_source}
    end
  end

  defp safe_page_filename?(filename) do
    Path.basename(filename) == filename and String.ends_with?(filename, ".png")
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> text("Not Found")
  end
end
