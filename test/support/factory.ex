defmodule AlchemIiif.Factory do
  @moduledoc """
  テスト用のデータファクトリモジュール。
  各スキーマのテストデータ生成ヘルパーを提供します。
  """
  alias AlchemIiif.IIIF.Manifest
  alias AlchemIiif.Ingestion.{ExtractedImage, PdfSource}
  alias AlchemIiif.Repo

  # === PdfSource ファクトリ ===

  @doc "PdfSource の属性マップを生成"
  def pdf_source_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        filename: "test_report_#{System.unique_integer([:positive])}.pdf",
        page_count: 10,
        status: "ready"
      },
      overrides
    )
  end

  @doc "PdfSource レコードを作成・挿入"
  def insert_pdf_source(overrides \\ %{}) do
    attrs = pdf_source_attrs(overrides)

    changeset = PdfSource.changeset(%PdfSource{}, attrs)

    # user_id が指定されている場合は changeset に追加
    changeset =
      if Map.has_key?(overrides, :user_id) do
        Ecto.Changeset.put_change(changeset, :user_id, overrides[:user_id])
      else
        changeset
      end

    Repo.insert!(changeset)
  end

  # === ExtractedImage ファクトリ ===

  @doc "ExtractedImage の属性マップを生成"
  def extracted_image_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        page_number: 1,
        image_path: "priv/static/uploads/pages/test/page-001.png",
        geometry: %{"x" => 10, "y" => 20, "width" => 200, "height" => 300},
        caption: "第1図 テスト土器",
        label: "fig-#{System.unique_integer([:positive])}-1",
        site: "テスト市遺跡",
        period: "縄文時代",
        artifact_type: "土器",
        status: "draft"
      },
      overrides
    )
  end

  @doc "ExtractedImage レコードを作成・挿入（PdfSource を自動生成）"
  def insert_extracted_image(overrides \\ %{}) do
    # pdf_source_id が指定されていなければ自動生成
    attrs =
      if Map.has_key?(overrides, :pdf_source_id) do
        extracted_image_attrs(overrides)
      else
        pdf_source = insert_pdf_source()
        extracted_image_attrs(Map.put(overrides, :pdf_source_id, pdf_source.id))
      end

    %ExtractedImage{}
    |> ExtractedImage.changeset(attrs)
    |> Repo.insert!()
  end

  # === Manifest ファクトリ ===

  @doc "Manifest の属性マップを生成"
  def manifest_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        identifier: "img-test-#{System.unique_integer([:positive])}",
        metadata: %{
          "label" => %{"en" => ["Test Image"], "ja" => ["テスト画像"]},
          "summary" => %{"en" => ["Test"], "ja" => ["テスト"]}
        }
      },
      overrides
    )
  end

  @doc "Manifest レコードを作成・挿入（ExtractedImage を自動生成）"
  def insert_manifest(overrides \\ %{}) do
    # extracted_image_id が指定されていなければ自動生成
    attrs =
      if Map.has_key?(overrides, :extracted_image_id) do
        manifest_attrs(overrides)
      else
        image = insert_extracted_image(%{ptif_path: "/tmp/test.tif"})
        manifest_attrs(Map.put(overrides, :extracted_image_id, image.id))
      end

    %Manifest{}
    |> Manifest.changeset(attrs)
    |> Repo.insert!()
  end

  # === User ファクトリ ===

  @doc "テスト用ユーザーを作成・挿入（AccountsFixtures に委譲）。role 指定時は挿入後に更新。"
  def insert_user(overrides \\ %{}) do
    {role, rest} = Map.pop(overrides, :role)
    user = AlchemIiif.AccountsFixtures.user_fixture(rest)

    if role && role != "user" do
      user
      |> Ecto.Changeset.change(%{role: role})
      |> AlchemIiif.Repo.update!()
    else
      user
    end
  end
end
