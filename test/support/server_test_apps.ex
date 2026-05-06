defmodule ExRatatui.Test.ServerApps do
  @moduledoc """
  Shared `ExRatatui.App` fixtures for `ExRatatui.Server` unit tests.

  Each app echoes lifecycle events back to a `test_pid` taken from the
  `mount/1` opts so tests can drive the server via messages and assert on
  the callbacks that fired.
  """

  defmodule Echo do
    @moduledoc """
    Generic lifecycle echo — used by the local, SSH, and distributed
    transport test suites.

    State: `%{test_pid, count}`. `count` starts at 0 and increments on each
    `handle_event` call.

    Renders a single `Paragraph` covering the full frame so transports that
    care about ANSI/BEAM-term draw output (SSH, distributed) always have
    non-trivial bytes to assert on.

    Messages sent to `test_pid`:

      * `{:mounted, opts}` — on mount
      * `{:rendered, count, frame}` — on render
      * `{:event, event}` — on handle_event
      * `{:info, msg}` — on handle_info (non-transport messages)
      * `{:terminated, reason}` — on terminate
    """

    use ExRatatui.App

    alias ExRatatui.Layout.Rect
    alias ExRatatui.Widgets.Paragraph

    @impl true
    def mount(opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      send(test_pid, {:mounted, opts})
      {:ok, %{test_pid: test_pid, count: 0}}
    end

    @impl true
    def render(state, frame) do
      send(state.test_pid, {:rendered, state.count, frame})

      [
        {%Paragraph{text: "count: #{state.count}"},
         %Rect{x: 0, y: 0, width: frame.width, height: frame.height}}
      ]
    end

    @impl true
    def handle_event(event, state) do
      send(state.test_pid, {:event, event})
      {:noreply, %{state | count: state.count + 1}}
    end

    @impl true
    def handle_info(msg, state) do
      send(state.test_pid, {:info, msg})
      {:noreply, state}
    end

    @impl true
    def terminate(reason, state) do
      send(state.test_pid, {:terminated, reason})
      :ok
    end
  end

  defmodule StopOnAnyEvent do
    @moduledoc "Returns `{:stop, state}` from every `handle_event` call."

    use ExRatatui.App

    @impl true
    def mount(opts) do
      {:ok, %{test_pid: Keyword.get(opts, :test_pid)}}
    end

    @impl true
    def render(_state, _frame), do: []

    @impl true
    def handle_event(_event, state), do: {:stop, state}
  end

  defmodule FailingMount do
    @moduledoc "Returns `{:error, :mount_failed}` from `mount/1`."

    use ExRatatui.App

    @impl true
    def mount(_opts), do: {:error, :mount_failed}

    @impl true
    def render(_state, _frame), do: []

    @impl true
    def handle_event(_event, state), do: {:noreply, state}
  end

  defmodule Intents do
    @moduledoc """
    Emits intents in `mount/1`, `handle_event/2`, and `handle_info/2`
    transitions to exercise the runtime's intent plumbing.

    Mount opts:
      * `:mount_intents` — list of intents the runtime should ship after mount
      * `:test_pid` — required for lifecycle tracing

    Events:
      * `%Key{code: "navigate"}` — emit `{:navigate, "/dashboard"}` and continue
      * `%Key{code: "stop_with_intent"}` — emit `{:redirect, "/login"}` and stop
      * any other event — continue with no intents
    """

    use ExRatatui.App

    alias ExRatatui.Event.Key

    @impl true
    def mount(opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      mount_intents = Keyword.get(opts, :mount_intents, [])
      send(test_pid, {:mounted, opts})
      {:ok, %{test_pid: test_pid}, intents: mount_intents}
    end

    @impl true
    def render(_state, frame) do
      alias ExRatatui.Layout.Rect
      alias ExRatatui.Widgets.Paragraph

      [
        {%Paragraph{text: "intents fixture"},
         %Rect{x: 0, y: 0, width: frame.width, height: frame.height}}
      ]
    end

    @impl true
    def handle_event(%Key{code: "navigate"}, state) do
      {:noreply, state, intents: [{:navigate, "/dashboard"}]}
    end

    def handle_event(%Key{code: "stop_with_intent"}, state) do
      {:stop, state, intents: [{:redirect, "/login"}]}
    end

    def handle_event(%Key{code: "bogus_intents"}, state) do
      {:noreply, state, intents: :not_a_list}
    end

    def handle_event(_event, state), do: {:noreply, state}

    @impl true
    def handle_info({:emit_intents, intents}, state) do
      {:noreply, state, intents: intents}
    end

    def handle_info(_msg, state), do: {:noreply, state}
  end
end
