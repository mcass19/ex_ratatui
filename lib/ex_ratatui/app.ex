defmodule ExRatatui.App do
  @moduledoc """
  A behaviour for building supervised TUI applications.

  Provides a LiveView-inspired callback interface for terminal apps
  that can be placed in OTP supervision trees.

  ## Usage

      defmodule MyTUI do
        use ExRatatui.App

        @impl true
        def mount(_opts) do
          {:ok, %{count: 0}}
        end

        @impl true
        def render(state, frame) do
          alias ExRatatui.Widgets.Paragraph
          alias ExRatatui.Layout.Rect

          widget = %Paragraph{text: "Count: \#{state.count}"}
          rect = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}
          [{widget, rect}]
        end

        @impl true
        def handle_event(%ExRatatui.Event.Key{code: "q"}, state) do
          {:stop, state}
        end

        def handle_event(_event, state) do
          {:noreply, state}
        end
      end

  Then add to your supervision tree:

      children = [{MyTUI, []}]
      Supervisor.start_link(children, strategy: :one_for_one)

  ## Runtimes

  `ExRatatui.App` supports two runtime styles:

    * Callback runtime (default) — implement `mount/1`, `render/2`,
      `handle_event/2`, and optionally `handle_info/2`
    * Reducer runtime — `use ExRatatui.App, runtime: :reducer` and
      implement `init/1`, `render/2`, `update/2`, and optionally
      `subscriptions/1`

  Reducer apps receive all terminal input as `{:event, event}` and all
  mailbox messages as `{:info, msg}` through `update/2`. They can return:

    * `commands: [...]` to schedule side effects after the state transition
    * `render?: false` to skip the immediate render
    * `trace?: true | false` to toggle runtime trace collection

  ## Options

  Options are passed through `start_link/1` and forwarded to `mount/1`:

    * `:transport` - which transport to serve the TUI over. One of:
      * `:local` (default) — drives the OS process' real tty via crossterm.
        This is the path you want for a desktop TUI launched from a shell.
      * `:ssh` — starts an SSH daemon that gives every connecting client
        its own isolated session and `user_state`. Requires the `:port`
        option (and usually `:authorized_keys` / `:system_dir`); see
        `ExRatatui.SSH.Daemon` for the full option list.
      * `:distributed` — starts a listener that waits for remote BEAM
        nodes to attach via `ExRatatui.Distributed.attach/2`. Each
        attaching node gets its own isolated session. No Rust NIF is
        loaded on the app node — widget lists travel as BEAM terms and
        the client renders them locally. See `ExRatatui.Distributed`.
    * `:name` - process registration name (defaults to the module name,
      pass `nil` to skip registration)
    * `:poll_interval` - event polling interval in milliseconds (default: `16`,
      which gives ~60fps). The poll runs on the BEAM's DirtyIo scheduler so it
      never blocks normal processes. Lower values increase responsiveness but
      use more CPU; higher values reduce CPU but add input latency.
      Only used by the `:local` transport.
    * `:test_mode` - `{width, height}` tuple to use a headless test terminal
      instead of the real terminal. This disables live terminal input polling
      so tests stay isolated and `async: true` safe; use
      `ExRatatui.Runtime.inject_event/2` to drive input deterministically.

  The same app module can be supervised under multiple transports
  simultaneously — `mount/1`, `render/2`, `handle_event/2` and
  `handle_info/2` are transport-agnostic:

      children = [
        {MyApp.TUI, []},                                      # local TTY
        {MyApp.TUI, transport: :ssh, port: 2222, ...},        # remote over SSH
        {MyApp.TUI, transport: :distributed}                   # remote over distribution
      ]

  ## Callbacks

    * `mount/1` — Called once on startup with options. Return
      `{:ok, initial_state}`, `{:ok, initial_state, runtime_opts}`, or
      `{:error, reason}` to abort startup.
    * `init/1` — Reducer runtime startup callback. Return `{:ok, initial_state}`
      or `{:ok, initial_state, runtime_opts}`.
    * `render/2` — Called after every state change. Receives state and a
      `%ExRatatui.Frame{}` with terminal dimensions. Return a list of
      `{widget, rect}` tuples.
    * `handle_event/2` — Called when a terminal event arrives. Return
      `{:noreply, new_state}` or `{:stop, state}`.
    * `handle_info/2` — Called for non-terminal messages (e.g., PubSub).
      Optional; default implementation returns `{:noreply, state}`.
    * `update/2` — Reducer runtime message handler. Receives `{:event, event}`
      and `{:info, msg}` and returns `{:noreply, state}`, `{:stop, state}`,
      or either form with reducer runtime opts.
    * `subscriptions/1` — Reducer runtime subscription declaration.
      Optional; default implementation returns `[]`.
    * `terminate/2` — Called when the TUI is shutting down. Receives the
      exit reason and final state. Optional; default is a no-op.
      Use this to stop the VM with `System.stop(0)` in standalone apps.
  """

  @type state :: term()
  @type callback_opts :: keyword()

  alias ExRatatui.Distributed.Listener
  alias ExRatatui.SSH.Daemon

  @doc """
  Called once on startup with the options passed to `start_link/1`.

  Return `{:ok, initial_state}`, `{:ok, initial_state, runtime_opts}`, or
  `{:error, reason}` to abort.
  """
  @callback mount(opts :: keyword()) ::
              {:ok, state()} | {:ok, state(), callback_opts()} | {:error, reason :: term()}

  @doc """
  Reducer runtime entrypoint.

  Only used when the module does `use ExRatatui.App, runtime: :reducer`.
  """
  @callback init(opts :: keyword()) ::
              {:ok, state()} | {:ok, state(), callback_opts()} | {:error, reason :: term()}

  @doc """
  Called after every state change to produce the UI.

  Receives the current state and a `%ExRatatui.Frame{}` with the terminal
  dimensions. Return a list of `{widget, rect}` tuples to render.
  """
  @callback render(state(), ExRatatui.Frame.t()) :: [
              {ExRatatui.widget(), ExRatatui.Layout.Rect.t()}
            ]

  @doc """
  Called when a terminal event (key, mouse, or resize) arrives.

  Return `{:noreply, new_state}` to continue or `{:stop, state}` to
  shut down the application.
  """
  @callback handle_event(
              ExRatatui.Event.Key.t() | ExRatatui.Event.Mouse.t() | ExRatatui.Event.Resize.t(),
              state()
            ) ::
              {:noreply, state()} | {:stop, state()}

  @doc """
  Called for non-terminal messages (e.g. PubSub broadcasts, `send/2`).

  Optional — the default implementation returns `{:noreply, state}`.
  """
  @callback handle_info(msg :: term(), state()) :: {:noreply, state()} | {:stop, state()}

  @doc """
  Reducer runtime message handler.

  Only used when the module does `use ExRatatui.App, runtime: :reducer`.
  Messages are wrapped as `{:event, event}` and `{:info, msg}`.
  """
  @callback update(msg :: term(), state()) ::
              {:noreply, state()}
              | {:noreply, state(), callback_opts()}
              | {:stop, state()}
              | {:stop, state(), callback_opts()}

  @doc """
  Returns the subscriptions desired for the current state.
  """
  @callback subscriptions(state()) :: [ExRatatui.Subscription.t()]

  @doc """
  Called when the TUI is shutting down.

  Receives the exit reason and the final state. Optional — the default
  is a no-op. Use this to call `System.stop(0)` in standalone apps.
  """
  @callback terminate(reason :: term(), state()) :: term()

  @optional_callbacks [handle_info: 2, terminate: 2, init: 1, update: 2, subscriptions: 1]

  defmacro __using__(opts) do
    runtime = Keyword.get(opts, :runtime, :callbacks)

    case runtime do
      :callbacks ->
        quote do
          @behaviour ExRatatui.App

          @doc false
          def __runtime__, do: :callbacks

          @doc false
          def handle_info(_msg, state), do: {:noreply, state}

          @doc false
          def subscriptions(_state), do: []

          @doc false
          def terminate(_reason, _state), do: :ok

          defoverridable handle_info: 2, subscriptions: 1, terminate: 2, __runtime__: 0

          @doc false
          def child_spec(opts) do
            %{
              id: __MODULE__,
              start: {__MODULE__, :start_link, [opts]},
              type: :worker,
              restart: :transient
            }
          end

          @doc false
          def start_link(opts \\ []) when is_list(opts) do
            opts |> Keyword.put(:mod, __MODULE__) |> ExRatatui.App.dispatch_start()
          end
        end

      :reducer ->
        quote do
          @behaviour ExRatatui.App

          @doc false
          def __runtime__, do: :reducer

          @doc false
          def mount(opts), do: ExRatatui.App.reducer_mount(__MODULE__, opts)

          @doc false
          def handle_event(event, state),
            do: ExRatatui.App.reducer_handle_event(__MODULE__, event, state)

          @doc false
          def handle_info(msg, state),
            do: ExRatatui.App.reducer_handle_info(__MODULE__, msg, state)

          @doc false
          def subscriptions(_state), do: []

          @doc false
          def terminate(_reason, _state), do: :ok

          defoverridable subscriptions: 1, terminate: 2, __runtime__: 0

          @doc false
          def child_spec(opts) do
            %{
              id: __MODULE__,
              start: {__MODULE__, :start_link, [opts]},
              type: :worker,
              restart: :transient
            }
          end

          @doc false
          def start_link(opts \\ []) when is_list(opts) do
            opts |> Keyword.put(:mod, __MODULE__) |> ExRatatui.App.dispatch_start()
          end
        end

      other ->
        raise ArgumentError, "unsupported ExRatatui.App runtime: #{inspect(other)}"
    end
  end

  @doc false
  def reducer_mount(mod, opts), do: mod.init(opts)

  @doc false
  def reducer_handle_event(mod, event, state), do: mod.update({:event, event}, state)

  @doc false
  def reducer_handle_info(mod, msg, state), do: mod.update({:info, msg}, state)

  @doc false
  # Routes a `use ExRatatui.App` start_link call to the right transport
  # supervisor. Public so it can be unit-tested directly without going
  # through a generated start_link/1.
  def dispatch_start(opts) do
    case Keyword.get(opts, :transport, :local) do
      :local ->
        ExRatatui.Server.start_link(opts)

      :ssh ->
        Daemon.start_link(opts)

      :distributed ->
        Listener.start_link(opts)
    end
  end
end
