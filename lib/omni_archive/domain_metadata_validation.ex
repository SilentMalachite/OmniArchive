defmodule OmniArchive.DomainMetadataValidation do
  @moduledoc """
  active profile に従って metadata 系フィールドを検証します。
  """

  import Ecto.Changeset

  alias OmniArchive.DomainProfiles
  alias OmniArchive.Ingestion.ExtractedImageMetadata

  def validate_changeset(changeset) do
    Enum.reduce(validated_fields(), changeset, fn field, acc ->
      validate_changeset_field(acc, field)
    end)
  end

  def validate_field(field, value) do
    field = normalize_field(field)

    case DomainProfiles.validation_rule(field) do
      nil ->
        nil

      rule ->
        value = to_string(value || "")

        cond do
          value == "" -> nil
          max_length_exceeded?(rule, value) -> rule[:max_length_error]
          format_invalid?(rule, value) -> rule[:format_error]
          required_terms_invalid?(rule, value) -> rule[:required_terms_error]
          true -> nil
        end
    end
  end

  def max_length(field) do
    field
    |> normalize_field()
    |> DomainProfiles.validation_rule()
    |> case do
      nil -> nil
      rule -> Map.get(rule, :max_length)
    end
  end

  def duplicate_scope_field do
    DomainProfiles.duplicate_scope_field()
  end

  def duplicate_label_error do
    DomainProfiles.duplicate_label_error()
  end

  defp validate_changeset_field(changeset, field) do
    rule = DomainProfiles.validation_rule!(field)
    value = changeset_field_value(changeset, field)

    changeset
    |> maybe_validate_max_length(field, value, rule)
    |> maybe_validate_format(field, value, rule)
    |> maybe_validate_required_terms(field, value, rule)
  end

  defp maybe_validate_max_length(changeset, field, value, rule) do
    if max_length_exceeded?(rule, value) do
      add_error(changeset, error_field(field), rule.max_length_error)
    else
      changeset
    end
  end

  defp maybe_validate_format(changeset, field, value, rule) do
    if format_invalid?(rule, value) do
      add_error(changeset, error_field(field), rule.format_error)
    else
      changeset
    end
  end

  defp maybe_validate_required_terms(changeset, field, value, rule) do
    if required_terms_invalid?(rule, value) do
      add_error(changeset, error_field(field), rule.required_terms_error)
    else
      changeset
    end
  end

  defp max_length_exceeded?(%{max_length: max_length}, value) when is_binary(value),
    do: value != "" and String.length(value) > max_length

  defp max_length_exceeded?(_, _), do: false

  defp format_invalid?(%{format: format}, value) when is_binary(value),
    do: value != "" and not Regex.match?(format, value)

  defp format_invalid?(_, _), do: false

  defp required_terms_invalid?(%{required_terms: required_terms}, value) when is_binary(value),
    do: value != "" and not String.contains?(value, required_terms)

  defp required_terms_invalid?(_, _), do: false

  defp validated_fields do
    rules = DomainProfiles.validation_rules()

    DomainProfiles.metadata_fields()
    |> Enum.map(& &1.field)
    |> Enum.filter(fn field ->
      Enum.any?(rules, fn {rule_field, _rule} ->
        field_key(rule_field) == field_key(field)
      end)
    end)
  end

  defp normalize_field(field) do
    key = field_key(field)

    DomainProfiles.metadata_fields()
    |> Enum.find(&(field_key(&1.field) == key))
    |> case do
      nil -> field
      metadata_field -> metadata_field.field
    end
  end

  defp changeset_field_value(changeset, field) do
    case ExtractedImageMetadata.schema_field_atom(field) do
      nil ->
        changeset
        |> get_field(:metadata)
        |> metadata_value(field)

      atom ->
        get_field(changeset, atom)
    end
  end

  defp metadata_value(metadata, field) when is_map(metadata) do
    Map.get(metadata, field_key(field))
  end

  defp metadata_value(_metadata, _field), do: nil

  defp error_field(field) when is_atom(field), do: field
  defp error_field(_field), do: :metadata

  defp field_key(field) when is_atom(field), do: Atom.to_string(field)
  defp field_key(field) when is_binary(field), do: field
  defp field_key(field), do: to_string(field)
end
