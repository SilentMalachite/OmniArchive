defmodule OmniArchive.DomainProfile do
  @moduledoc """
  ドメイン固有のメタデータ定義を切り替えるための behaviour。
  """

  @type metadata_field :: %{
          required(:field) => atom(),
          required(:label) => String.t(),
          required(:placeholder) => String.t(),
          optional(:storage) => :core | :metadata
        }

  @type search_facet :: %{
          required(:field) => atom(),
          required(:param) => String.t(),
          required(:label) => String.t()
        }

  @callback metadata_fields() :: [metadata_field()]
  @callback validation_rules() :: map()
  @callback search_facets() :: [search_facet()]
  @callback ui_texts() :: map()
end
