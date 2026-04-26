defmodule OmniArchive.DomainProfiles do
  @moduledoc """
  有効なドメイン profile へのアクセサ。
  コンパイル時フィールドとランタイムカスタムフィールドをマージして返します。
  """

  alias OmniArchive.CustomMetadataFields
  alias OmniArchive.CustomMetadataFields.Cache
  alias OmniArchive.DomainProfiles.GeneralArchive

  @default_profile GeneralArchive
  @compile_time_default_profile Application.compile_env(
                                  :omni_archive,
                                  :domain_profile,
                                  @default_profile
                                )

  def current do
    Application.get_env(:omni_archive, :domain_profile, @compile_time_default_profile)
  end

  def metadata_fields do
    current().metadata_fields() ++ runtime_metadata_fields()
  end

  def metadata_field!(field) do
    key = field_key(field)

    Enum.find(metadata_fields(), &(field_key(&1.field) == key)) ||
      raise ArgumentError, "unknown metadata field: #{inspect(field)}"
  end

  def validation_rules do
    compile_time = current().validation_rules()
    runtime = runtime_validation_rules()
    Map.merge(compile_time, runtime)
  end

  def validation_rule!(field) do
    validation_rule(field) || raise KeyError, key: field, term: validation_rules()
  end

  def validation_rule(field) do
    rules = validation_rules()
    key = field_key(field)

    Enum.find_value(rules, fn {rule_field, rule} ->
      if field_key(rule_field) == key, do: rule
    end)
  end

  def search_facets do
    current().search_facets() ++ runtime_search_facets()
  end

  def ui_texts do
    current().ui_texts()
  end

  def ui_text(path) when is_list(path) do
    get_in(ui_texts(), path) || raise ArgumentError, "unknown UI text path: #{inspect(path)}"
  end

  def duplicate_identity do
    current().duplicate_identity()
  end

  def profile_key do
    duplicate_identity().profile_key
  end

  def duplicate_scope_field do
    duplicate_identity().scope_field
  end

  def duplicate_label_error do
    duplicate_identity().duplicate_label_error
  end

  # --- ランタイムフィールド統合 ---

  defp runtime_metadata_fields do
    Cache.list_active_fields(profile_key())
    |> Enum.map(&CustomMetadataFields.to_profile_format/1)
  end

  defp runtime_validation_rules do
    Cache.list_active_fields(profile_key())
    |> Enum.map(&CustomMetadataFields.to_validation_rule/1)
    |> Enum.reject(fn {_k, v} -> v == %{} end)
    |> Enum.into(%{})
  end

  defp runtime_search_facets do
    Cache.list_active_fields(profile_key())
    |> Enum.filter(& &1.searchable)
    |> Enum.map(&CustomMetadataFields.to_search_facet/1)
  end

  defp field_key(field) when is_atom(field), do: Atom.to_string(field)
  defp field_key(field) when is_binary(field), do: field
  defp field_key(field), do: to_string(field)
end
