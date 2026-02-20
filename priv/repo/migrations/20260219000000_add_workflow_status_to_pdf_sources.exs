defmodule AlchemIiif.Repo.Migrations.AddWorkflowStatusToPdfSources do
  use Ecto.Migration

  def change do
    alter table(:pdf_sources) do
      # ワークフローステータス: wip → pending_review → returned / approved
      add :workflow_status, :string, null: false, default: "wip"
      # 差し戻し時の管理者メッセージ
      add :return_message, :text
    end
  end
end
