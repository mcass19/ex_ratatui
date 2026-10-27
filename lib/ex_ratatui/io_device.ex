defmodule ExRatatui.IODevice do
  @moduledoc """
  Runs an `ExRatatui.App` on an Erlang I/O device — typically the group
  leader of the shell we were called from.

  The `:local` transport drives the operating-system terminal the BEAM was
  started on. That is the wrong terminal whenever the shell isn't: an IEx
  session over SSH (`nerves_ssh`, `ExRatatui.SSH` shell mode) or an
  `iex --remsh` attached from another machine. Started from there, a
  `:local` app takes over the device's console instead of the screen in
  front of us. This transport renders through the shell's own I/O device
  instead, the way any IEx output reaches the user:

      iex> ExRatatui.IODevice.run(MyApp.TUI)

  Frames are rendered by an `ExRatatui.Session` and written with
  `put_chars` requests; keys are read one character at a time with
  `get_chars` (echo off) and decoded by the session's input parser, so
  they arrive in `handle_event/2` exactly as over SSH. The I/O protocol
  has no resize notification, so the device's size is polled every
  250 ms. The device's echo and binary options are put back when the app
  stops.

  `io_device?/1` tells the two cases apart, so a launcher can pick this
  transport only when the local terminal isn't ours.

  ## Options

  `run/2` takes the same options as an app's `start_link/1`, minus
  `:transport` and `:name`, plus:

    * `:device` — the I/O device to use (default: the caller's group
      leader).
    * `:keyboard_enhancement` — ask the terminal for key repeat and
      release events, as over SSH. See
      [Key releases](building_uis.html#key-releases).
  """

  use GenServer

  @behaviour ExRatatui.Transport

  alias ExRatatui.Event
  alias ExRatatui.Session
  alias ExRatatui.Transport.ByteStream

  # Same screen setup and teardown as `ExRatatui.SSH`: alternate screen,
  # hidden cursor, and the kitty keyboard flags pushed inside it.
  @enter_screen "\e[?1049h\e[?25l"
  @leave_screen "\e[?1049l\e[?25h\e[0m"
  @push_keyboard_enhancement "\e[>15u"
  @pop_keyboard_enhancement "\e[<u"

  @esc_timeout_ms 50
  @resize_interval_ms 250
  @driver_timeout_ms 250

  defstruct [
    :device,
    :device_opts,
    :session,
    :server_pid,
    :read_ref,
    :size,
    esc_timer: nil,
    keyboard_enhancement: false,
    resize_interval_ms: @resize_interval_ms
  ]

  @doc """
  Runs `mod` on the I/O device until the app stops.

  Blocks the caller, like `ExRatatui.run/2`; meant for an IEx helper.
  Returns `:ok` when the app stops normally, `{:error, reason}` when it
  can't start (the device refused the options, say) or crashes.

  ## Examples

      # A device that can't turn echo off is refused before anything is drawn.
      iex> {:ok, device} = StringIO.open("")
      iex> ExRatatui.IODevice.run(MyApp.TUI, device: device)
      {:error, {:io_device, {:error, :enotsup}}}
  """
  @spec run(module(), keyword()) :: :ok | {:error, term()}
  def run(mod, opts \\ []) when is_atom(mod) and is_list(opts) do
    device = opts |> Keyword.get_lazy(:device, &Process.group_leader/0) |> GenServer.whereis()

    case GenServer.start(__MODULE__, {mod, device, opts}) do
      {:ok, pid} -> await(pid)
      {:error, reason} -> {:error, reason}
    end
  end

  defp await(pid) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, reason} when reason in [:normal, :shutdown] -> :ok
      {:DOWN, ^ref, :process, ^pid, {:shutdown, _}} -> :ok
      {:DOWN, ^ref, :process, ^pid, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns `true` when `device` isn't the terminal this node was started
  on: the group leader of an SSH shell, or of an `iex --remsh` attached
  from another node.

  Asks the device's group process for its driver and compares it with
  this node's `:user_drv`. A device that doesn't answer (a `StringIO`, a
  test's captured output) counts as local.

  ## Examples

      iex> {:ok, device} = StringIO.open("")
      iex> ExRatatui.IODevice.io_device?(device)
      false
  """
  @spec io_device?(pid() | atom()) :: boolean()
  def io_device?(device \\ Process.group_leader()) do
    case GenServer.whereis(device) do
      pid when is_pid(pid) -> remote_driver?(pid, driver(pid))
      _ -> false
    end
  end

  defp remote_driver?(_device, nil), do: false

  # A node without a terminal of its own (`-noshell`, a release) has no
  # `:user_drv`, so any driver it finds belongs to someone else's shell.
  defp remote_driver?(_device, driver),
    do: driver not in for(name <- [:user_drv], pid = Process.whereis(name), do: pid)

  # OTP 28+ groups answer `{:driver_id, pid}` in any state. OTP 26/27
  # ones don't while a read is pending; they keep the driver in their
  # process dictionary instead.
  defp driver(device) do
    send(device, {:driver_id, self()})

    receive do
      {^device, :driver_id, driver} when is_pid(driver) -> driver
    after
      @driver_timeout_ms -> dictionary_driver(device)
    end
  end

  defp dictionary_driver(device) do
    case :erpc.call(
           node(device),
           :erlang,
           :process_info,
           [device, :dictionary],
           @driver_timeout_ms
         ) do
      {:dictionary, dictionary} -> Keyword.get(dictionary, :user_drv)
      _ -> nil
    end
  catch
    # The device's node is unreachable or too slow to answer: no driver to
    # compare, so the device counts as local. `process_info/2` itself can't
    # raise there, on a pid of its own node.
    :error, {:erpc, _reason} -> nil
  end

  ## GenServer callbacks

  @impl true
  def init({mod, device, opts}) do
    Process.flag(:trap_exit, true)
    Process.monitor(device)

    with device_opts when is_list(device_opts) <- :io.getopts(device),
         :ok <- :io.setopts(device, echo: false, binary: true) do
      {width, height} = device_size(device)

      state = %__MODULE__{
        device: device,
        device_opts: Keyword.take(device_opts, [:echo, :binary]),
        session: Session.new(width, height),
        size: {width, height},
        keyboard_enhancement: Keyword.get(opts, :keyboard_enhancement, false),
        resize_interval_ms: Keyword.get(opts, :resize_interval_ms, @resize_interval_ms)
      }

      start_server(state, mod, opts)
    else
      error -> {:stop, {:io_device, error}}
    end
  end

  defp start_server(state, mod, opts) do
    write(state.device, enter_screen(state))

    server_opts =
      opts
      |> Keyword.drop([:device, :resize_interval_ms, :transport, :name])
      |> Keyword.merge(
        mod: mod,
        name: nil,
        transport: {:session, state.session, fn bytes -> write(state.device, bytes) end}
      )

    case ExRatatui.Server.start_link(server_opts) do
      {:ok, pid} ->
        state = request_input(%{state | server_pid: pid})
        Process.send_after(self(), :check_size, state.resize_interval_ms)
        {:ok, state}

      {:error, reason} ->
        restore(state)
        {:stop, reason}
    end
  end

  @impl true
  def handle_info({:io_reply, ref, data}, %__MODULE__{read_ref: ref} = state)
      when is_binary(data) do
    state = state |> cancel_esc_timer() |> request_input()
    events = ByteStream.forward_input(state.session, state.server_pid, data)

    # A chunk that ends on 0x1B and decodes to nothing may be a bare Esc
    # the parser is holding as the start of a sequence: give the rest of
    # the sequence 50 ms to arrive, then call it Esc. See `ExRatatui.SSH`.
    if events == [] and data != "" and :binary.last(data) == 0x1B,
      do: {:noreply, arm_esc_timer(state)},
      else: {:noreply, state}
  end

  # `:eof` or `{:error, _}`: the shell went away.
  def handle_info({:io_reply, ref, _closed}, %__MODULE__{read_ref: ref} = state),
    do: {:stop, :normal, state}

  def handle_info(:esc_timeout, %__MODULE__{} = state) do
    Session.reset_parser(state.session)
    send(state.server_pid, {:ex_ratatui_event, %Event.Key{code: "esc", kind: "press"}})
    {:noreply, %{state | esc_timer: nil}}
  end

  # Asked asynchronously so a slow device never stalls reading.
  def handle_info(:check_size, %__MODULE__{} = state) do
    for {axis, request} <- [width: :columns, height: :rows] do
      send(state.device, {:io_request, self(), {:geometry, axis}, {:get_geometry, request}})
    end

    Process.send_after(self(), :check_size, state.resize_interval_ms)
    {:noreply, state}
  end

  def handle_info({:io_reply, {:geometry, axis}, value}, %__MODULE__{size: {w, h}} = state)
      when is_integer(value) and value > 0 do
    size = if axis == :width, do: {value, h}, else: {w, value}

    if size != state.size do
      {width, height} = size
      :ok = ByteStream.forward_resize(state.session, state.server_pid, width, height)
    end

    {:noreply, %{state | size: size}}
  end

  def handle_info({:io_reply, {:geometry, _axis}, _unknown}, state), do: {:noreply, state}

  # The app stopped: hand the shell back. A crash is passed on, so
  # `run/2` returns it as an error.
  def handle_info({:EXIT, pid, reason}, %__MODULE__{server_pid: pid} = state)
      when reason in [:normal, :shutdown],
      do: {:stop, :normal, %{state | server_pid: nil}}

  def handle_info({:EXIT, pid, reason}, %__MODULE__{server_pid: pid} = state),
    do: {:stop, reason, %{state | server_pid: nil}}

  def handle_info({:DOWN, _ref, :process, device, _reason}, %__MODULE__{device: device} = state),
    do: {:stop, :normal, %{state | device: nil}}

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %__MODULE__{} = state) do
    if state.server_pid, do: stop_server(state.server_pid)
    restore(state)
    :ok
  end

  ## Helpers

  defp request_input(%__MODULE__{device: device} = state) do
    ref = make_ref()
    send(device, {:io_request, self(), ref, {:get_chars, :unicode, "", 1}})
    %{state | read_ref: ref}
  end

  # A closed device answers `{:error, _}`, which is fine to drop: the
  # `:DOWN` (or the read's error reply) stops us anyway.
  defp write(device, bytes) do
    _ = :io.request(device, {:put_chars, :unicode, bytes})
    :ok
  end

  defp restore(%__MODULE__{device: nil} = state), do: Session.close(state.session)

  defp restore(%__MODULE__{device: device} = state) do
    write(device, leave_screen(state))
    _ = :io.setopts(device, state.device_opts)
    Session.close(state.session)
  end

  defp stop_server(pid) do
    Process.unlink(pid)
    Process.exit(pid, :shutdown)
  end

  defp arm_esc_timer(%__MODULE__{} = state) do
    ref = Process.send_after(self(), :esc_timeout, @esc_timeout_ms)
    %{state | esc_timer: ref}
  end

  defp cancel_esc_timer(%__MODULE__{esc_timer: nil} = state), do: state

  defp cancel_esc_timer(%__MODULE__{esc_timer: ref} = state) do
    Process.cancel_timer(ref)

    receive do
      :esc_timeout -> :ok
    after
      0 -> :ok
    end

    %{state | esc_timer: nil}
  end

  defp device_size(device) do
    with {:ok, width} when width > 0 <- :io.columns(device),
         {:ok, height} when height > 0 <- :io.rows(device) do
      {width, height}
    else
      _ -> {80, 24}
    end
  end

  defp enter_screen(%__MODULE__{keyboard_enhancement: true}),
    do: @enter_screen <> @push_keyboard_enhancement

  defp enter_screen(_state), do: @enter_screen

  defp leave_screen(%__MODULE__{keyboard_enhancement: true}),
    do: @pop_keyboard_enhancement <> @leave_screen

  defp leave_screen(_state), do: @leave_screen
end
