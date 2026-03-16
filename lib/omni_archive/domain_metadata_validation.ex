defmodule OmniArchive.DomainMetadataValidation do
  @moduledoc """
  active profile に従って metadata 系フィールドを検証します。
  """

  import Ecto.Changeset

  alias OmniArchive.DomainProfiles

  def validate_changeset(changeset) do
    Enum.reduce(validated_fields(), changeset, fn field, acc ->
      validate_changeset_field(acc, field)
    end)
  end

  def validate_field(field, value) do
    field = normalize_field(field)
    rule = DomainProfiles.validation_rule!(field)
    value = to_string(value || "")

    cond do
      value == "" -> nil
      max_length_exceeded?(rule, value) -> rule.max_length_error
      format_invalid?(rule, value) -> rule.format_error
      required_terms_invalid?(rule, value) -> rule.required_terms_error
      true -> nil
    end
  end

  def max_length(field) do
    field
    |> normalize_field()
    |> DomainProfiles.validation_rule!()
    |> Map.get(:max_length)
  end

  def duplicate_scope_field do
    DomainProfiles.duplicate_scope_field()
  end

  def duplicate_label_error do
    DomainProfiles.duplicate_label_error()
  end

  defp validate_changeset_field(changeset, field) do
    rule = DomainProfiles.validation_rule!(field)
    value = get_field(changeset, field)

    changeset
    |> maybe_validate_max_length(field, value, rule)
    |> maybe_validate_format(field, value, rule)
    |> maybe_validate_required_terms(field, value, rule)
  end

  defp maybe_validate_max_length(changeset, field, value, rule) do
    if max_length_exceeded?(rule, value) do
      add_error(changeset, field, rule.max_length_error)
    else
      changeset
    end
  end

  defp maybe_validate_format(changeset, field, value, rule) do
    if format_invalid?(rule, value) do
      add_error(changeset, field, rule.format_error)
    else
      changeset
    end
  end

  defp maybe_validate_required_terms(changeset, field, value, rule) do
    if required_terms_invalid?(rule, value) do
      add_error(changeset, field, rule.required_terms_error)
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
    DomainProfiles.metadata_fields()
    |> Enum.map(& &1.field)
    |> Enum.filter(&Map.has_key?(DomainProfiles.validation_rules(), &1))
  end

  defp normalize_field(field) when is_atom(field), do: field
  defp normalize_field(field) when is_binary(field), do: String.to_existing_atom(field)
end
