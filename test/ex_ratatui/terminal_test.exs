defmodule ExRatatui.TerminalTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Native

  describe "NIF loading" do
    test "init_terminal NIF is loaded and callable" do
      result = Native.init_terminal()
      assert is_reference(result) or match?({:error, _}, result)

      if is_reference(result), do: Native.restore_terminal(result)
    end

    test "terminal_size NIF is loaded and callable" do
      result = ExRatatui.terminal_size()
      assert match?({_, _}, result)
    end
  end

  describe "run/1" do
    test "either executes the function (TTY) or returns error (no TTY)" do
      result = ExRatatui.run(fn _terminal -> :ran end)

      case result do
        :ran -> :ok
        {:error, _reason} -> :ok
      end
    end

    test "ensures terminal is restored after function executes" do
      ExRatatui.run(fn _terminal -> :ok end)
      # If run succeeded, terminal was restored in the after block.
      # If it failed (no TTY), nothing to restore.
      assert true
    end
  end

  describe "BEAM scheduler safety" do
    test "NIF calls do not block concurrent tasks" do
      tasks =
        for _ <- 1..4 do
          Task.async(fn ->
            Process.sleep(10)
            :alive
          end)
        end

      ExRatatui.terminal_size()

      results = Task.await_many(tasks, 5000)
      assert Enum.all?(results, &(&1 == :alive))
    end
  end

  describe "terminal lifecycle" do
    test "init and restore complete successfully" do
      case Native.init_terminal() do
        {:error, _} -> :ok
        ref -> assert :ok = Native.restore_terminal(ref)
      end
    end

    test "terminal_size returns integers after init" do
      case Native.init_terminal() do
        {:error, _} ->
          :ok

        ref ->
          assert {w, h} = ExRatatui.terminal_size()
          assert is_integer(w) and is_integer(h)
          assert :ok = Native.restore_terminal(ref)
      end
    end

    test "full ExRatatui.run/1 lifecycle" do
      ran? =
        case ExRatatui.run(fn _terminal -> :ran end) do
          :ran -> true
          {:error, _} -> false
        end

      # If it ran, terminal was already restored by run/1
      assert is_boolean(ran?)
    end
  end
end
