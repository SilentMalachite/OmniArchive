defmodule OmniArchive.DomainProfilesTest do
  use ExUnit.Case, async: true

  alias OmniArchive.DomainProfiles
  alias OmniArchive.DomainProfiles.GeneralArchive

  test "active profile defaults to GeneralArchive" do
    assert DomainProfiles.current() == GeneralArchive
  end

  test "search facet definitions match GeneralArchive" do
    assert DomainProfiles.search_facets() == [
             %{field: :collection, param: "collection", label: "🗂️ コレクション"},
             %{field: :item_type, param: "item_type", label: "📁 資料種別"},
             %{field: :date_note, param: "date_note", label: "📅 年代メモ"}
           ]
  end

  test "duplicate identity defaults to GeneralArchive" do
    assert DomainProfiles.profile_key() == "general_archive"
    assert DomainProfiles.duplicate_scope_field() == :collection
  end
end
