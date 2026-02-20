defmodule ProjectRenamer do
  @targets [
    {"OmniArchive", "OmniArchive"},
    {"omni_archive", "omni_archive"},
    {"OmniArchive", "OmniArchive"}
  ]

  @ignore_dirs [
    ".git",
    "deps",
    "_build",
    "node_modules",
    "assets/node_modules",
    "priv/static",
    ".elixir_ls"
  ]

  @ignore_exts [
    ".png", ".jpg", ".jpeg", ".gif", ".ico", ".svg", ".woff", ".woff2", ".ttf", ".eot", ".beam", ".gz", ".tar", ".pdf", ".zip"
  ]

  def run(dir) do
    walk(dir)
  end

  defp walk(dir) do
    dir
    |> File.ls!()
    |> Enum.each(fn file ->
      path = Path.join(dir, file)
      cond do
        File.dir?(path) ->
          if file not in @ignore_dirs do
            walk(path)
          end
        File.regular?(path) ->
          process_file(path)
        true ->
          :ok
      end
    end)
  end

  defp process_file(path) do
    ext = Path.extname(path) |> String.downcase()
    if ext not in @ignore_exts do
      case File.read(path) do
        {:ok, content} ->
          if String.valid?(content) do
            new_content = Enum.reduce(@targets, content, fn {search, replace}, acc ->
              String.replace(acc, search, replace)
            end)
            if content != new_content do
              File.write!(path, new_content)
              IO.puts("Updated: #{path}")
            end
          end
        _ -> :ok
      end
    end
  end
end

ProjectRenamer.run(".")
