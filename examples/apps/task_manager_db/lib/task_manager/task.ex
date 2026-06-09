defmodule TaskManager.Task do
  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(todo in_progress done)
  @priorities [1, 2, 3]

  schema "tasks" do
    field(:title, :string)
    field(:status, :string, default: "todo")
    field(:priority, :integer, default: 2)

    timestamps(type: :utc_datetime)
  end

  def changeset(task, attrs) do
    fields = [:title, :status, :priority]

    task
    |> cast(attrs, fields)
    |> validate_required(fields)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:priority, @priorities)
  end
end
