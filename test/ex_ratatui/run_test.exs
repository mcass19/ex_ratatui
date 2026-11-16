defmodule ExRatatui.RunTest do
  # async: false — swaps the application-wide function that opens the
  # terminal (see test_helper.exs) for one that hands back a headless one.
  use ExUnit.Case, async: false

  setup do
    previous = Application.fetch_env!(:ex_ratatui, :init_terminal_fn)
    test_pid = self()

    Application.put_env(:ex_ratatui, :init_terminal_fn, fn focus_events?, mouse_capture? ->
      send(test_pid, {:init_terminal, focus_events?, mouse_capture?})
      ExRatatui.init_test_terminal(20, 5)
    end)

    on_exit(fn -> Application.put_env(:ex_ratatui, :init_terminal_fn, previous) end)
  end

  describe "run/2" do
    test "opens the terminal, runs the function and restores it" do
      assert {:ran, terminal} = ExRatatui.run(fn terminal -> {:ran, terminal} end)

      assert_received {:init_terminal, false, false}
      assert {:error, _} = ExRatatui.get_buffer_content(terminal)
    end

    test "passes :focus_events and :mouse_capture on" do
      assert :ok = ExRatatui.run(fn _terminal -> :ok end, focus_events: true, mouse_capture: true)

      assert_received {:init_terminal, true, true}
    end

    test "restores the terminal when the function raises" do
      test_pid = self()

      assert_raise RuntimeError, "boom", fn ->
        ExRatatui.run(fn terminal ->
          send(test_pid, {:terminal, terminal})
          raise "boom"
        end)
      end

      assert_received {:terminal, terminal}
      assert {:error, _} = ExRatatui.get_buffer_content(terminal)
    end
  end

  describe "the :local runtime" do
    defmodule App do
      use ExRatatui.App

      @impl true
      def mount(_opts), do: {:ok, nil}

      @impl true
      def render(_state, _frame), do: []

      @impl true
      def handle_event(_event, state), do: {:noreply, state}
    end

    test "opens the terminal with its start options" do
      Process.flag(:trap_exit, true)
      test_pid = self()

      # Refused, so no server is left polling the suite's own input.
      Application.put_env(:ex_ratatui, :init_terminal_fn, fn focus_events?, mouse_capture? ->
        send(test_pid, {:init_terminal, focus_events?, mouse_capture?})
        {:error, :refused}
      end)

      assert {:error, {:terminal_init_failed, :refused}} =
               ExRatatui.Server.start_link(
                 mod: App,
                 name: nil,
                 focus_events: true,
                 mouse_capture: true
               )

      assert_received {:init_terminal, true, true}
    end
  end
end
