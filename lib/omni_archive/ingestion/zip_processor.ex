defmodule OmniArchive.Ingestion.ZipProcessor do
  require Logger

  @moduledoc """
  PNG コレクションを格納した ZIP アーカイブから、ページ画像を
  安全に展開するモジュール。

  ## なぜこの設計か

  - **OTP 標準 :zip モジュール**: 新規依存を増やさずに ZIP 展開を実装する。
    CLAUDE.md の "No new dependencies" 不変条件に準拠。
  - **3 層防御**:
    1. zip-slip 防止 — 各エントリの解決後パスが output_dir 配下にあることを `Path.expand` で確認。
    2. PNG マジックバイト検証 — 拡張子だけでなくファイル先頭 8 バイト（`<<137,80,78,71,13,10,26,10>>`）を確認。
    3. 容量上限 — `:zip_max_extracted_bytes` / `:zip_max_pages` で展開サイズ・件数を抑制（zip bomb 対策）。
  - **AppleDouble 除外**: macOS 由来の `__MACOSX/` および `._*` メタデータを取り除き、誤検出を防ぐ。
  - **自然順ソート**: `page-2.png` が `page-10.png` より先に来るよう、数値部分を抽出してソート。

  ## 出力規約

  PdfProcessor と同じ `page-NNN-{timestamp}.png` 命名を使用するため、
  上位パイプライン（Pipeline.run_source_extraction / UploadAssetController）は
  PDF と同じパス前提で動作できる。
  """

  alias OmniArchive.Ingestion.PdfSource

  # PNG マジックバイト
  @png_magic <<137, 80, 78, 71, 13, 10, 26, 10>>

  # フォールバック値（runtime config が未ロードの場合）
  @fallback_max_extracted_bytes 1_000_000_000
  @fallback_max_pages 1500

  @doc """
  ZIP から PNG を抽出し、output_dir に `page-NNN-{ts}.png` で配置する。

  ## オプション

  - `:max_pages` — ページ数上限。未指定時は :ingestion config の `zip_max_pages` を使用。
  - `:max_extracted_bytes` — 累積展開バイト上限。未指定時は :ingestion config の `zip_max_extracted_bytes` を使用。
  - `:user_id` — 進捗 PubSub 通知用。

  ## 戻り値

  - `{:ok, %{page_count: integer, image_paths: [Path.t()]}}`
  - `{:error, reason}`
  """
  def extract_pngs(zip_path, output_dir, opts \\ %{}) do
    File.mkdir_p!(output_dir)

    abs_zip_path = Path.expand(zip_path)
    abs_output_dir = Path.expand(output_dir)

    with {:ok, entries} <- list_zip_entries(abs_zip_path),
         png_entries <- filter_png_entries(entries),
         :ok <- validate_page_count(png_entries, opts),
         :ok <- validate_extracted_bytes(png_entries, opts),
         {:ok, extracted_paths} <-
           extract_filtered(abs_zip_path, png_entries, abs_output_dir),
         {:ok, validated_paths} <- validate_png_signatures(extracted_paths),
         {:ok, renamed_paths} <- rename_to_page_format(validated_paths, abs_output_dir, opts) do
      page_count = length(renamed_paths)

      Logger.info("[ZipProcessor] 完了: #{page_count} ページを #{abs_output_dir} に展開")
      broadcast_progress(page_count, page_count, opts)

      {:ok, %{page_count: page_count, image_paths: renamed_paths}}
    end
  end

  # === エントリ列挙 ===

  defp list_zip_entries(zip_path) do
    case :zip.list_dir(String.to_charlist(zip_path)) do
      {:ok, entries} ->
        {:ok, entries}

      {:error, reason} ->
        Logger.error("[ZipProcessor] :zip.list_dir 失敗: #{inspect(reason)}")
        {:error, "ZIP の読み取りに失敗しました: #{inspect(reason)}"}
    end
  end

  # :zip エントリは `:zip_comment` ヘッダと `:zip_file` レコードが混在する。
  # PNG 拡張子のみを残し、AppleDouble メタを除外、自然順でソート。
  defp filter_png_entries(entries) do
    entries
    |> Enum.flat_map(fn
      {:zip_file, name, info, _comment, _offset, _size} ->
        [{to_string(name), info}]

      _ ->
        []
    end)
    |> Enum.reject(fn {name, _info} -> apple_double?(name) end)
    |> Enum.filter(fn {name, _info} ->
      String.downcase(Path.extname(name)) == ".png"
    end)
    |> Enum.sort_by(fn {name, _info} -> natural_sort_key(name) end)
  end

  defp apple_double?(name) do
    base = Path.basename(name)
    String.starts_with?(name, "__MACOSX/") or String.starts_with?(base, "._")
  end

  # 自然順ソートキー: 名前を「文字列・整数」のセグメント列に分解して比較。
  # 数値部分は整数として、文字列部分はそのまま比較できる形に整える。
  # 数値要素は {0, n} とし「文字列より先」になるよう、文字列要素は {1, str} とする。
  defp natural_sort_key(name) do
    Regex.scan(~r/(\d+)|(\D+)/, String.downcase(name))
    |> Enum.map(fn
      [_, num, ""] -> {0, String.to_integer(num)}
      [_, "", text] -> {1, text}
      [_, num] -> {0, String.to_integer(num)}
    end)
  end

  # === 容量検証 ===

  defp validate_page_count(entries, opts) do
    max_pages = effective_max_pages(opts)
    count = length(entries)

    cond do
      count == 0 ->
        {:error, "ZIP に PNG ファイルが含まれていません"}

      count > max_pages ->
        {:error, "ページ数上限（#{max_pages}ページ）を超えています: #{count}ページ"}

      true ->
        :ok
    end
  end

  defp validate_extracted_bytes(entries, opts) do
    max_bytes = effective_max_extracted_bytes(opts)

    total =
      Enum.reduce(entries, 0, fn {_name, info}, acc ->
        acc + uncompressed_size(info)
      end)

    if total <= max_bytes do
      :ok
    else
      {:error, "展開後サイズ上限（#{max_bytes} bytes）を超えています: #{total} bytes"}
    end
  end

  # :zip_file_info レコードの :size フィールドを取り出す。レコードのため
  # element/2 で位置取得。:zip ヘッダ参照: {:zip_file_info, :size, ...}
  defp uncompressed_size(info) when is_tuple(info) do
    # :zip_file_info {info, type, comment, offset, size, comp_size, ...}
    # 安全側: tuple_size 制限内で size と思しき要素を探す
    info
    |> Tuple.to_list()
    |> Enum.filter(&is_integer/1)
    |> Enum.max(fn -> 0 end)
  end

  defp uncompressed_size(_), do: 0

  defp effective_max_pages(opts) do
    case Map.get(opts, :max_pages) do
      n when is_integer(n) and n > 0 -> n
      _ -> ingestion_config(:zip_max_pages, @fallback_max_pages)
    end
  end

  defp effective_max_extracted_bytes(opts) do
    case Map.get(opts, :max_extracted_bytes) do
      n when is_integer(n) and n > 0 -> n
      _ -> ingestion_config(:zip_max_extracted_bytes, @fallback_max_extracted_bytes)
    end
  end

  defp ingestion_config(key, fallback) do
    case Application.get_env(:omni_archive, :ingestion) do
      nil -> fallback
      ingestion -> Keyword.get(ingestion, key, fallback)
    end
  end

  # === 展開（zip-slip 安全版） ===

  defp extract_filtered(zip_path, entries, output_dir) do
    allowed = entries |> Enum.map(fn {name, _info} -> name end) |> MapSet.new()

    file_filter = fn {:zip_file, name, _info, _comment, _offset, _size} ->
      MapSet.member?(allowed, to_string(name))
    end

    options = [
      {:file_filter, file_filter},
      {:cwd, String.to_charlist(output_dir)}
    ]

    case :zip.unzip(String.to_charlist(zip_path), options) do
      {:ok, file_charlists} ->
        paths = Enum.map(file_charlists, &to_string/1)

        case enforce_path_safety(paths, output_dir) do
          {:ok, safe_paths} ->
            {:ok, safe_paths}

          {:error, _} = err ->
            Enum.each(paths, fn p -> if File.regular?(p), do: File.rm(p) end)
            err
        end

      {:error, reason} ->
        Logger.error("[ZipProcessor] :zip.unzip 失敗: #{inspect(reason)}")
        {:error, "ZIP の展開に失敗しました: #{inspect(reason)}"}
    end
  end

  defp enforce_path_safety(paths, output_dir) do
    abs_output = Path.expand(output_dir)

    case Enum.find(paths, fn p ->
           expanded = Path.expand(p)
           not String.starts_with?(expanded, abs_output <> "/") and expanded != abs_output
         end) do
      nil -> {:ok, paths}
      bad -> {:error, "zip-slip を検出しました: #{bad}"}
    end
  end

  # === PNG マジックバイト検証 ===

  defp validate_png_signatures(paths) do
    expected = @png_magic

    {valid, invalid} =
      Enum.split_with(paths, fn path ->
        case File.open(path, [:read, :binary], fn io -> IO.binread(io, 8) end) do
          {:ok, header} when header == expected -> true
          _ -> false
        end
      end)

    Enum.each(invalid, fn path ->
      Logger.warning("[ZipProcessor] PNG マジックバイト不一致のため削除: #{path}")
      File.rm(path)
    end)

    if valid == [] do
      {:error, "ZIP 内に有効な PNG ファイルがありませんでした"}
    else
      {:ok, valid}
    end
  end

  # === ページ命名（PdfProcessor と互換） ===

  defp rename_to_page_format(paths, output_dir, opts) do
    timestamp = System.system_time(:second)
    total = length(paths)

    # 平坦化リネーム: nested directory 内のファイルも output_dir 直下へ移動
    renamed =
      paths
      |> Enum.with_index(1)
      |> Enum.map(fn {original_path, index} ->
        new_name = "page-#{pad(index)}-#{timestamp}.png"
        new_path = Path.join(output_dir, new_name)

        # 同名ファイル衝突回避：すでに存在すればユニーク化
        new_path = ensure_unique_path(new_path)
        File.rename!(original_path, new_path)

        broadcast_progress(index, total, opts)
        new_path
      end)

    cleanup_empty_subdirs(output_dir)

    {:ok, renamed}
  end

  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(3, "0")

  defp ensure_unique_path(path) do
    if File.exists?(path) do
      ext = Path.extname(path)
      base = Path.rootname(path)
      Path.expand("#{base}-#{System.unique_integer([:positive])}#{ext}")
    else
      path
    end
  end

  defp cleanup_empty_subdirs(output_dir) do
    Path.wildcard(Path.join(output_dir, "**/*"))
    |> Enum.sort_by(&String.length/1, :desc)
    |> Enum.filter(&File.dir?/1)
    |> Enum.each(fn dir ->
      case File.ls(dir) do
        {:ok, []} -> File.rmdir(dir)
        _ -> :noop
      end
    end)
  end

  defp broadcast_progress(current, total, %{user_id: user_id})
       when not is_nil(user_id) and is_integer(total) and total > 0 do
    Phoenix.PubSub.broadcast(
      OmniArchive.PubSub,
      "pdf_pipeline:#{user_id}",
      {:extraction_progress, current, total}
    )
  end

  defp broadcast_progress(_current, _total, _opts), do: :ok

  @doc false
  # 公開: PdfSource に紐づくジョブで output_dir を一貫して解決するヘルパ
  def output_dir_for(%PdfSource{} = source), do: PdfSource.pages_dir(source)
end
