defmodule TaskManager do
  @moduledoc """
  Context module for task management operations.
  """

  import Ecto.Query

  alias TaskManager.Repo
  alias TaskManager.Task

  def list_tasks(:all) do
    Repo.all(from(t in Task, order_by: [asc: t.inserted_at]))
  end

  def list_tasks(status) when is_atom(status) do
    status_str = Atom.to_string(status)
    Repo.all(from(t in Task, where: t.status == ^status_str, order_by: [asc: t.inserted_at]))
  end

  def create_task(attrs) do
    %Task{}
    |> Task.changeset(attrs)
    |> Repo.insert()
  end

  def update_task(%Task{} = task, attrs) do
    task
    |> Task.changeset(attrs)
    |> Repo.update()
  end

  def delete_task(%Task{} = task) do
    Repo.delete(task)
  end

  def toggle_status(%Task{} = task) do
    next = next_status(task.status)
    update_task(task, %{status: next})
  end

  def cycle_priority(%Task{} = task) do
    next = next_priority(task.priority)
    update_task(task, %{priority: next})
  end

  def completion_stats do
    total = Repo.aggregate(Task, :count)
    done = Repo.one(from(t in Task, where: t.status == "done", select: count()))
    {total, done}
  end

  defp next_status("todo"), do: "in_progress"
  defp next_status("in_progress"), do: "done"
  defp next_status("done"), do: "todo"
  defp next_status(_), do: "todo"

  defp next_priority(1), do: 2
  defp next_priority(2), do: 3
  defp next_priority(3), do: 1
  defp next_priority(_), do: 2
end
