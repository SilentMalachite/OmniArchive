defmodule OmniArchive.DomainProfiles.YamlLoader do
  @moduledoc """
  YAML ファイルからドメインプロファイル定義を読込・検証する。
  """

  @field_key_format ~r/^[a-z][a-z0-9_]{0,49}$/
  @core_allowed_fields ~w[summary label]
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
  @allowed_storage_atoms %{"core" => :core, "metadata" => :metadata}
  @allowed_rule_error_atoms %{
    "max_length_error" => :max_length_error,
    "format_error" => :format_error,
    "required_terms_error" => :required_terms_error
  }

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
    if Regex.match?(@field_key_format, key) do
      storage = Map.get(f, "storage", "metadata")

      if storage in ["core", "metadata"] do
        {:ok,
         %{
           field: key,
           label: label,
           placeholder: Map.get(f, "placeholder", ""),
           storage: Map.fetch!(@allowed_storage_atoms, storage)
         }}
      else
        {:error, "invalid storage for #{key}: #{inspect(storage)}"}
      end
    else
      {:error, "invalid field key: #{inspect(key)}"}
    end
  end

  defp normalize_field(other),
    do: {:error, "metadata_fields entry must have field/label: #{inspect(other)}"}

  defp ensure_unique_field_keys(fields) do
    keys = Enum.map(fields, &field_key(&1.field))

    case keys -- Enum.uniq(keys) do
      [] -> :ok
      dups -> {:error, "duplicate field keys: #{inspect(dups)}"}
    end
  end

  defp ensure_core_fields_present(fields) do
    required = @core_allowed_fields
    present = Enum.map(fields, &field_key(&1.field))

    case required -- present do
      [] ->
        Enum.reduce_while(required, :ok, fn field, _ ->
          case Enum.find(fields, &(field_key(&1.field) == field)) do
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
        f.storage == :core and field_key(f.field) not in @core_allowed_fields
      end)

    case bad do
      [] -> :ok
      [%{field: f} | _] -> {:error, "storage: core not allowed for #{f}"}
    end
  end

  @allowed_rule_keys ~w[max_length max_length_error format format_error required_terms required_terms_error]

  defp parse_validation_rules(raw, _fields) when not is_map(raw),
    do: {:error, "validation_rules must be a mapping"}

  defp parse_validation_rules(raw, fields) do
    fields_by_key = fields_by_key(fields)

    Enum.reduce_while(raw, {:ok, %{}}, fn {field_str, rules}, {:ok, acc} ->
      case Map.fetch(fields_by_key, field_str) do
        :error ->
          {:halt, {:error, "validation_rules references unknown field: #{field_str}"}}

        {:ok, field} ->
          if is_map(rules) do
            case normalize_rule(rules) do
              {:ok, normalized} -> {:cont, {:ok, Map.put(acc, field, normalized)}}
              {:error, _} = err -> {:halt, err}
            end
          else
            {:halt, {:error, "validation_rules.#{field_str} must be a mapping"}}
          end
      end
    end)
  end

  defp fields_by_key(fields) do
    Map.new(fields, fn field -> {field_key(field.field), field.field} end)
  end

  defp normalize_rule(rules) do
    Enum.reduce_while(rules, {:ok, %{}}, fn {k, v}, {:ok, acc} ->
      case normalize_rule_entry(k, v) do
        {:ok, key, val} -> {:cont, {:ok, Map.put(acc, key, val)}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp normalize_rule_entry(k, _v) when k not in @allowed_rule_keys,
    do: {:error, "unknown rule key: #{k}"}

  defp normalize_rule_entry("format", v) when is_binary(v) do
    case Regex.compile(v) do
      {:ok, re} -> {:ok, :format, re}
      {:error, reason} -> {:error, "invalid format regex: #{inspect(reason)}"}
    end
  end

  defp normalize_rule_entry("required_terms", v) when is_list(v) do
    if Enum.all?(v, &is_binary/1),
      do: {:ok, :required_terms, v},
      else: {:error, "required_terms must be list of strings"}
  end

  defp normalize_rule_entry("max_length", v) when is_integer(v) and v > 0,
    do: {:ok, :max_length, v}

  defp normalize_rule_entry(k, v) when is_binary(v) and k != "" do
    case Map.fetch(@allowed_rule_error_atoms, k) do
      {:ok, atom} -> {:ok, atom, v}
      :error -> {:error, "invalid value for rule #{k}"}
    end
  end

  defp normalize_rule_entry(k, _v),
    do: {:error, "invalid value for rule #{k}"}

  defp parse_search_facets(raw, _fields) when not is_list(raw),
    do: {:error, "search_facets must be a list"}

  defp parse_search_facets(raw, fields) do
    fields_by_key = fields_by_key(fields)

    map_while_ok(raw, fn
      %{"field" => f, "param" => p, "label" => l}
      when is_binary(f) and is_binary(p) and is_binary(l) ->
        case Map.fetch(fields_by_key, f) do
          {:ok, field} -> {:ok, %{field: field, param: p, label: l}}
          :error -> {:error, "search_facets references unknown field: #{f}"}
        end

      other ->
        {:error, "invalid facet entry: #{inspect(other)}"}
    end)
  end

  defp parse_ui_texts(raw) when not is_map(raw),
    do: {:error, "ui_texts must be a mapping"}

  defp parse_ui_texts(raw) do
    with {:ok, search} <- parse_ui_section(raw["search"], @required_search_keys, "search"),
         {:ok, inspector} <-
           parse_ui_section(raw["inspector_label"], @required_inspector_keys, "inspector_label") do
      {:ok, %{search: search, inspector_label: inspector}}
    end
  end

  defp parse_ui_section(nil, _keys, name), do: {:error, "ui_texts.#{name} is required"}

  defp parse_ui_section(raw, required_keys, name) when is_map(raw) do
    missing =
      Enum.filter(required_keys, fn k ->
        val = Map.get(raw, Atom.to_string(k))
        not (is_binary(val) and val != "")
      end)

    case missing do
      [] ->
        result =
          for k <- required_keys, into: %{} do
            {k, Map.fetch!(raw, Atom.to_string(k))}
          end

        {:ok, result}

      keys ->
        {:error, "ui_texts.#{name} missing keys: #{inspect(keys)}"}
    end
  end

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
    fields_by_key = fields_by_key(fields)

    with v when is_binary(v) <- Map.get(map, key) || :missing,
         {:ok, field} <- Map.fetch(fields_by_key, v) do
      {:ok, field}
    else
      _ -> {:error, "#{key} must reference a defined metadata field"}
    end
  end

  defp fetch_field_ref_default(map, key, default, fields) do
    raw = Map.get(map, key, default)
    fetch_field_ref(%{key => raw}, key, fields)
  end

  defp field_key(field) when is_atom(field), do: Atom.to_string(field)
  defp field_key(field) when is_binary(field), do: field

  defp map_while_ok(list, fun) do
    Enum.reduce_while(list, {:ok, []}, fn elem, {:ok, acc} ->
      case fun.(elem) do
        {:ok, v} -> {:cont, {:ok, acc ++ [v]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end
end
