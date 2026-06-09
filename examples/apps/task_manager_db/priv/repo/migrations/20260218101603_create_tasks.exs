defmodule TaskManager.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks) do
      add(:title, :string, null: false)
      add(:status, :string, null: false, default: "todo")
      add(:priority, :integer, null: false, default: 2)

      timestamps(type: :utc_datetime)
    end
  end
end
