defmodule TaskManagerTest do
  use ExUnit.Case

  alias TaskManager.Task

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TaskManager.Repo)
    :ok
  end

  describe "create_task/1" do
    test "creates a task with valid attrs" do
      assert {:ok, %Task{title: "Buy groceries"}} =
               TaskManager.create_task(%{title: "Buy groceries"})
    end

    test "returns error with missing title" do
      assert {:error, changeset} = TaskManager.create_task(%{})
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "defaults status to todo and priority to 2" do
      {:ok, task} = TaskManager.create_task(%{title: "Test task"})
      assert task.status == "todo"
      assert task.priority == 2
    end

    test "rejects invalid status" do
      assert {:error, changeset} =
               TaskManager.create_task(%{title: "Test", status: "invalid"})

      assert %{status: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "list_tasks/1" do
    test "returns all tasks when filter is :all" do
      {:ok, _} = TaskManager.create_task(%{title: "Task 1"})
      {:ok, _} = TaskManager.create_task(%{title: "Task 2", status: "done"})

      tasks = TaskManager.list_tasks(:all)
      assert length(tasks) == 2
    end

    test "filters tasks by status" do
      {:ok, _} = TaskManager.create_task(%{title: "Todo task", status: "todo"})
      {:ok, _} = TaskManager.create_task(%{title: "Done task", status: "done"})

      assert [%{title: "Todo task"}] = TaskManager.list_tasks(:todo)
      assert [%{title: "Done task"}] = TaskManager.list_tasks(:done)
    end

    test "returns empty list when no tasks match" do
      assert [] = TaskManager.list_tasks(:in_progress)
    end
  end

  describe "toggle_status/1" do
    test "cycles todo -> in_progress -> done -> todo" do
      {:ok, task} = TaskManager.create_task(%{title: "Cycle test"})
      assert task.status == "todo"

      {:ok, task} = TaskManager.toggle_status(task)
      assert task.status == "in_progress"

      {:ok, task} = TaskManager.toggle_status(task)
      assert task.status == "done"

      {:ok, task} = TaskManager.toggle_status(task)
      assert task.status == "todo"
    end
  end

  describe "delete_task/1" do
    test "deletes a task" do
      {:ok, task} = TaskManager.create_task(%{title: "Delete me"})
      assert {:ok, _} = TaskManager.delete_task(task)
      assert [] = TaskManager.list_tasks(:all)
    end
  end

  describe "completion_stats/0" do
    test "returns total and done counts" do
      {:ok, _} = TaskManager.create_task(%{title: "Done", status: "done"})
      {:ok, _} = TaskManager.create_task(%{title: "Todo", status: "todo"})
      {:ok, _} = TaskManager.create_task(%{title: "WIP", status: "in_progress"})

      assert {3, 1} = TaskManager.completion_stats()
    end

    test "returns {0, 0} with no tasks" do
      assert {0, 0} = TaskManager.completion_stats()
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
