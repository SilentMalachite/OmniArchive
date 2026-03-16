defmodule OmniArchive.DomainProfiles do
  @moduledoc """
  有効なドメイン profile へのアクセサ。
  """

  alias OmniArchive.DomainProfiles.Archaeology

  @default_profile Archaeology
  @current_profile Application.compile_env(:omni_archive, :domain_profile, @default_profile)

  def current do
    @current_profile
  end

  def metadata_fields do
    current().metadata_fields()
  end

  def metadata_field!(field) do
    Enum.find(metadata_fields(), &(&1.field == field)) ||
      raise ArgumentError, "unknown metadata field: #{inspect(field)}"
  end

  def validation_rules do
    current().validation_rules()
  end

  def validation_rule!(field) do
    Map.fetch!(validation_rules(), field)
  end

  def search_facets do
    current().search_facets()
  end

  def ui_texts do
    current().ui_texts()
  end

  def ui_text(path) when is_list(path) do
    get_in(ui_texts(), path) || raise ArgumentError, "unknown UI text path: #{inspect(path)}"
  end
end
