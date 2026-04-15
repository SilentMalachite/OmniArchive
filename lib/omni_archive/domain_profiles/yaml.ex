defmodule OmniArchive.DomainProfiles.Yaml do
  @moduledoc """
  YAML ファイルから読み込んだドメイン profile。
  実データは YamlCache から返す。
  """
  @behaviour OmniArchive.DomainProfile

  alias OmniArchive.DomainProfiles.YamlCache

  @impl true
  def metadata_fields, do: YamlCache.metadata_fields()

  @impl true
  def validation_rules, do: YamlCache.validation_rules()

  @impl true
  def search_facets, do: YamlCache.search_facets()

  @impl true
  def ui_texts, do: YamlCache.ui_texts()

  @impl true
  def duplicate_identity, do: YamlCache.duplicate_identity()
end
