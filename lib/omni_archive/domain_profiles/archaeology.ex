defmodule OmniArchive.DomainProfiles.Archaeology do
  @moduledoc """
  現行の考古学向けメタデータ定義。
  """

  @behaviour OmniArchive.DomainProfile

  @impl true
  def metadata_fields do
    [
      %{
        field: :caption,
        storage: :core,
        label: "📝 キャプション（図の説明）",
        placeholder: "例: 第3図 土器出土状況"
      },
      %{field: :label, storage: :core, label: "🏷️ ラベル（短い識別名）", placeholder: "例: fig-1-1"},
      %{field: :site, storage: :metadata, label: "📍 遺跡名（任意）", placeholder: "例: 新潟市中野遺跡"},
      %{field: :period, storage: :metadata, label: "⏳ 時代（任意）", placeholder: "例: 縄文時代"},
      %{field: :artifact_type, storage: :metadata, label: "🏺 遺物種別（任意）", placeholder: "例: 土器"}
    ]
  end

  @impl true
  def validation_rules do
    %{
      caption: %{
        max_length: 1000,
        max_length_error: "1000文字以内で入力してください"
      },
      label: %{
        format: ~r/^fig-\d+-\d+$/,
        format_error: "形式は 'fig-番号-番号' にしてください（例: fig-1-1）"
      },
      site: %{
        max_length: 30,
        max_length_error: "30文字以内で入力してください",
        required_terms: ["市", "町", "村"],
        required_terms_error: "市町村名（市・町・村）を含めてください（例: 新潟市中野遺跡）"
      },
      period: %{
        max_length: 30,
        max_length_error: "30文字以内で入力してください"
      },
      artifact_type: %{
        max_length: 30,
        max_length_error: "30文字以内で入力してください"
      },
      duplicate_scope_field: :site,
      duplicate_label_error: "この遺跡でそのラベルは既に登録されています"
    }
  end

  @impl true
  def search_facets do
    [
      %{field: :site, param: "site", label: "📍 遺跡名"},
      %{field: :period, param: "period", label: "⏳ 時代"},
      %{
        field: :artifact_type,
        param: "artifact_type",
        label: "🏺 遺物種別"
      }
    ]
  end

  @impl true
  def ui_texts do
    %{
      search: %{
        page_title: "画像を検索",
        heading: "🔍 画像を検索",
        description: "キーワードやフィルターで、登録済みの図版を検索できます。",
        placeholder: "キャプション、ラベル、遺跡名で検索...",
        empty_filtered: "条件に一致する図版が見つかりませんでした。",
        empty_filtered_hint: "検索キーワードやフィルターを変更してみてください。",
        empty_initial: "まだ図版が登録されていません。",
        empty_initial_hint: "Inspector から PDF をアップロードして図版を登録してください。",
        result_none: "結果なし",
        result_suffix: "件の図版が見つかりました",
        clear_filters: "✕ フィルターをクリア"
      },
      inspector_label: %{
        heading: "🏷️ 図版の情報を入力してください",
        description: "各フィールドに情報を入力してください。入力内容は自動的に保存されます。",
        duplicate_warning: "この遺跡でそのラベルは既に登録されています",
        duplicate_blocked: "⚠️ 重複ラベルがあります。ラベルを変更するか、既存レコードを更新してください。",
        duplicate_title: "重複先:",
        duplicate_edit: "📝 既存レコードを更新"
      }
    }
  end
end
