defmodule OmniArchive.Ingestion.ExtractedImageMetadata do
  @moduledoc """
  可変メタデータの dual-read / dual-write と backfill を扱います。
  """

  alias OmniArchive.DomainProfiles
  alias OmniArchive.Ingestion.ExtractedImage
  alias OmniArchive.Repo

  @doc "profile 上で metadata 保存対象になっているフィールド定義"
  def metadata_fields do
    DomainProfiles.metadata_fields()
    |> Enum.filter(&(Map.get(&1, :storage) == :metadata))
  end

  @doc "metadata 保存対象のフィールド名"
  def metadata_field_names do
    Enum.map(metadata_fields(), & &1.field)
  end

  @doc "Ecto schema 上に存在するフィールドか判定"
  def schema_field?(field) when is_atom(field) do
    field in ExtractedImage.__schema__(:fields)
  end

  @doc "metadata 優先、旧カラム fallback で値を取得"
  def read(%ExtractedImage{} = image, field) when is_atom(field) do
    metadata = normalize_metadata_map(image.metadata)
    key = Atom.to_string(field)

    if Map.has_key?(metadata, key) do
      Map.get(metadata, key)
    else
      read_legacy_field(image, field)
    end
  end

  def read(%ExtractedImage{} = image, field) when is_binary(field) do
    image
    |> read(String.to_existing_atom(field))
  rescue
    ArgumentError -> nil
  end

  def read(_image, _field), do: nil

  @doc "metadata 優先で profile 対象フィールドをマップ化"
  def read_map(%ExtractedImage{} = image) do
    Enum.reduce(metadata_field_names(), %{}, fn field, acc ->
      Map.put(acc, Atom.to_string(field), read(image, field))
    end)
  end

  @doc "attrs を metadata と旧カラムに同期する"
  def normalize_attrs(%ExtractedImage{} = image, attrs) when is_map(attrs) do
    current_metadata = normalize_metadata_map(image.metadata)
    provided_metadata = attrs |> fetch_attr(:metadata) |> metadata_from_attr()
    provided_legacy = extract_legacy_values(attrs)

    has_metadata_updates? =
      provided_metadata != %{} or provided_legacy != %{} or has_attr?(attrs, :metadata)

    merged_metadata =
      current_metadata
      |> Map.merge(provided_legacy)
      |> Map.merge(provided_metadata)

    attrs =
      if has_metadata_updates? do
        Map.put(attrs, :metadata, merged_metadata)
      else
        attrs
      end

    Enum.reduce(metadata_field_names(), attrs, fn field, acc ->
      maybe_put_legacy_attr(acc, field, merged_metadata)
    end)
  end

  @doc "旧カラムから metadata を backfill する"
  def backfill_from_legacy_fields do
    sql = """
    UPDATE extracted_images
    SET metadata = jsonb_strip_nulls(
      COALESCE(metadata, '{}'::jsonb) ||
      jsonb_build_object(
        'site', CASE WHEN COALESCE(metadata, '{}'::jsonb) ? 'site' THEN NULL ELSE NULLIF(site, '') END,
        'period', CASE WHEN COALESCE(metadata, '{}'::jsonb) ? 'period' THEN NULL ELSE NULLIF(period, '') END,
        'artifact_type', CASE WHEN COALESCE(metadata, '{}'::jsonb) ? 'artifact_type' THEN NULL ELSE NULLIF(artifact_type, '') END
      )
    )
    WHERE
      (NOT (COALESCE(metadata, '{}'::jsonb) ? 'site') AND site IS NOT NULL AND site != '') OR
      (NOT (COALESCE(metadata, '{}'::jsonb) ? 'period') AND period IS NOT NULL AND period != '') OR
      (NOT (COALESCE(metadata, '{}'::jsonb) ? 'artifact_type') AND artifact_type IS NOT NULL AND artifact_type != '')
    """

    %Postgrex.Result{num_rows: count} = Repo.query!(sql)
    count
  end

  defp extract_legacy_values(attrs) do
    Enum.reduce(metadata_field_names(), %{}, fn field, acc ->
      case fetch_attr(attrs, field) do
        {:ok, value} -> Map.put(acc, Atom.to_string(field), value)
        :error -> acc
      end
    end)
  end

  defp metadata_from_attr({:ok, value}) when is_map(value), do: normalize_metadata_map(value)
  defp metadata_from_attr(_), do: %{}

  defp normalize_metadata_map(metadata) when is_map(metadata) do
    Map.new(metadata, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_metadata_map(_), do: %{}

  defp fetch_attr(attrs, field) do
    cond do
      Map.has_key?(attrs, field) -> {:ok, Map.get(attrs, field)}
      Map.has_key?(attrs, Atom.to_string(field)) -> {:ok, Map.get(attrs, Atom.to_string(field))}
      true -> :error
    end
  end

  defp has_attr?(attrs, field) do
    Map.has_key?(attrs, field) or Map.has_key?(attrs, Atom.to_string(field))
  end

  defp read_legacy_field(image, field) do
    if schema_field?(field) do
      Map.get(image, field)
    else
      nil
    end
  end

  defp maybe_put_legacy_attr(attrs, field, merged_metadata) do
    key = Atom.to_string(field)

    if schema_field?(field) do
      case Map.fetch(merged_metadata, key) do
        {:ok, value} -> Map.put(attrs, field, value)
        :error -> attrs
      end
    else
      attrs
    end
  end
end
