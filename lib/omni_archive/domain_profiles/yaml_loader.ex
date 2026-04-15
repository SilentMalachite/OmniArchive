defmodule OmniArchive.DomainProfiles.YamlLoader do
  @moduledoc """
  YAML ファイルからドメインプロファイル定義を読込・検証する。
  """

  @field_key_format ~r/^[a-z][a-z0-9_]{0,49}$/
  @core_allowed_fields ~w[caption label]
  @required_search_keys ~w[
    page_title heading description placeholder
    empty_filtered empty_filtered_hint
    empty_initial empty_initial_hint
    result_none result_suffix clear_filters
  ]a
  @required_inspector_keys ~w[
    heading description
    duplicate_warning duplicate_blocked
    duplicate_title duplicate_edit
  ]a

  @spec load(Path.t()) :: {:ok, map()} | {:error, String.t()}
  def load(path) do
    with {:ok, raw} <- read_yaml(path),
         {:ok, fields} <- parse_metadata_fields(raw["metadata_fields"]),
         {:ok, rules} <- parse_validation_rules(raw["validation_rules"] || %{}, fields),
         {:ok, facets} <- parse_search_facets(raw["search_facets"] || [], fields),
         {:ok, ui} <- parse_ui_texts(raw["ui_texts"] || %{}),
         {:ok, dup} <- parse_duplicate_identity(raw["duplicate_identity"], fields) do
      {:ok,
       %{
         metadata_fields: fields,
         validation_rules: rules,
         search_facets: facets,
         ui_texts: ui,
         duplicate_identity: dup
       }}
    end
  end

  defp read_yaml(path) do
    case YamlElixir.read_from_file(path) do
      {:ok, data} when is_map(data) -> {:ok, data}
      {:ok, _} -> {:error, "YAML root must be a mapping"}
      {:error, reason} -> {:error, "YAML parse error: #{inspect(reason)}"}
    end
  end

  defp parse_metadata_fields(nil), do: {:error, "metadata_fields is required"}
  defp parse_metadata_fields([]), do: {:error, "metadata_fields must not be empty"}

  defp parse_metadata_fields(list) when is_list(list) do
    with {:ok, normalized} <- map_while_ok(list, &normalize_field/1),
         :ok <- ensure_unique_field_keys(normalized),
         :ok <- ensure_core_fields_present(normalized),
         :ok <- ensure_core_allowed(normalized) do
      {:ok, normalized}
    end
  end

  defp parse_metadata_fields(_), do: {:error, "metadata_fields must be a list"}

  defp normalize_field(%{"field" => key, "label" => label} = f)
       when is_binary(key) and is_binary(label) and label != "" do
    cond do
      not Regex.match?(@field_key_format, key) ->
        {:error, "invalid field key: #{inspect(key)}"}

      true ->
        storage = Map.get(f, "storage", "metadata")

        if storage not in ["core", "metadata"] do
          {:error, "invalid storage for #{key}: #{inspect(storage)}"}
        else
          {:ok,
           %{
             field: String.to_atom(key),
             label: label,
             placeholder: Map.get(f, "placeholder", ""),
             storage: String.to_atom(storage)
           }}
        end
    end
  end

  defp normalize_field(other),
    do: {:error, "metadata_fields entry must have field/label: #{inspect(other)}"}

  defp ensure_unique_field_keys(fields) do
    keys = Enum.map(fields, & &1.field)

    case keys -- Enum.uniq(keys) do
      [] -> :ok
      dups -> {:error, "duplicate field keys: #{inspect(dups)}"}
    end
  end

  defp ensure_core_fields_present(fields) do
    required = [:caption, :label]
    present = Enum.map(fields, & &1.field)

    case required -- present do
      [] ->
        Enum.reduce_while(required, :ok, fn field, _ ->
          case Enum.find(fields, &(&1.field == field)) do
            %{storage: :core} -> {:cont, :ok}
            _ -> {:halt, {:error, "#{field} must be defined with storage: core"}}
          end
        end)

      missing ->
        {:error, "required fields missing: #{inspect(missing)}"}
    end
  end

  defp ensure_core_allowed(fields) do
    bad =
      Enum.filter(fields, fn f ->
        f.storage == :core and Atom.to_string(f.field) not in @core_allowed_fields
      end)

    case bad do
      [] -> :ok
      [%{field: f} | _] -> {:error, "storage: core not allowed for #{f}"}
    end
  end

  defp parse_validation_rules(_raw, _fields), do: {:ok, %{}}

  defp parse_search_facets(_raw, _fields), do: {:ok, []}

  defp parse_ui_texts(_raw), do: {:ok, %{}}

  defp parse_duplicate_identity(nil, _), do: {:error, "duplicate_identity is required"}
  defp parse_duplicate_identity(raw, fields) when is_map(raw) do
    with {:ok, profile_key} <- fetch_string(raw, "profile_key"),
         {:ok, scope} <- fetch_field_ref(raw, "scope_field", fields),
         {:ok, label_field} <- fetch_field_ref_default(raw, "label_field", "label", fields),
         {:ok, err} <- fetch_string(raw, "duplicate_label_error") do
      {:ok,
       %{
         profile_key: profile_key,
         scope_field: scope,
         label_field: label_field,
         duplicate_label_error: err
       }}
    end
  end

  defp fetch_string(map, key) do
    case Map.get(map, key) do
      v when is_binary(v) and v != "" -> {:ok, v}
      _ -> {:error, "#{key} is required and must be a non-empty string"}
    end
  end

  defp fetch_field_ref(map, key, fields) do
    with v when is_binary(v) <- Map.get(map, key) || :missing,
         atom <- String.to_atom(v),
         true <- Enum.any?(fields, &(&1.field == atom)) do
      {:ok, atom}
    else
      _ -> {:error, "#{key} must reference a defined metadata field"}
    end
  end

  defp fetch_field_ref_default(map, key, default, fields) do
    raw = Map.get(map, key, default)
    fetch_field_ref(%{key => raw}, key, fields)
  end

  defp map_while_ok(list, fun) do
    Enum.reduce_while(list, {:ok, []}, fn elem, {:ok, acc} ->
      case fun.(elem) do
        {:ok, v} -> {:cont, {:ok, acc ++ [v]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end
end
