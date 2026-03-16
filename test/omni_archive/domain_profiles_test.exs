defmodule OmniArchive.DomainProfilesTest do
  use ExUnit.Case, async: true

  alias OmniArchive.DomainProfiles
  alias OmniArchive.DomainProfiles.Archaeology

  test "active profile defaults to archaeology" do
    assert DomainProfiles.current() == Archaeology
  end

  test "search facet definitions preserve current fields" do
    assert DomainProfiles.search_facets() == [
             %{field: :site, param: "site", label: "📍 遺跡名"},
             %{field: :period, param: "period", label: "⏳ 時代"},
             %{field: :artifact_type, param: "artifact_type", label: "🏺 遺物種別"}
           ]
  end

  test "duplicate identity defaults to archaeology" do
    assert DomainProfiles.profile_key() == "archaeology"
    assert DomainProfiles.duplicate_scope_field() == :site
  end
end
