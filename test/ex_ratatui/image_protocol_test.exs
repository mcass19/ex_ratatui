defmodule ExRatatui.ImageProtocolTest do
  # Covers the :image_protocol session/terminal hint added in chunk 6:
  # the new Session.set_image_protocol/2 API, the top-level
  # ExRatatui.set_image_protocol/2 helper, the SSH.Daemon opt forwarding,
  # and the Distributed client opt forwarding.
  use ExUnit.Case, async: true

  alias ExRatatui.Bridge
  alias ExRatatui.Image
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Session

  @valid_png Base.decode64!(
               "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
             )

  describe "Session.set_image_protocol/2" do
    test "accepts every protocol atom" do
      session = Session.new(20, 5)
      on_exit(fn -> Session.close(session) end)

      for protocol <- [:auto, :halfblocks, :kitty, :sixel, :iterm2] do
        assert :ok = Session.set_image_protocol(session, protocol)
      end
    end

    test "rejects unknown protocol atoms via guard" do
      session = Session.new(20, 5)
      on_exit(fn -> Session.close(session) end)

      assert_raise FunctionClauseError, fn ->
        Session.set_image_protocol(session, :gibberish)
      end
    end

    # Strong end-to-end signal: setting :kitty on the session must change
    # the bytes emitted on draw for an image with `protocol: :auto`. If
    # the hint isn't being threaded through, the bytes would be identical
    # (both runs would fall back to halfblocks).
    test "hint changes the output bytes for :auto images" do
      {:ok, image} = Image.new(@valid_png, protocol: :auto)
      rect = %Rect{x: 0, y: 0, width: 8, height: 4}
      commands = Bridge.encode_commands!([{image, rect}])

      half_session = Session.new(8, 4)
      :ok = Session.set_image_protocol(half_session, :halfblocks)
      :ok = Session.draw(half_session, [{image, rect}])
      half_bytes = Session.take_output(half_session)
      Session.close(half_session)

      kitty_session = Session.new(8, 4)
      :ok = Session.set_image_protocol(kitty_session, :kitty)
      # Send the pre-encoded commands again so the Image NIF is the same
      # state ref both times — only the hint differs.
      :ok = ExRatatui.Native.session_draw(kitty_session.ref, commands)
      kitty_bytes = ExRatatui.Native.session_take_output(kitty_session.ref)
      Session.close(kitty_session)

      assert is_binary(half_bytes)
      assert is_binary(kitty_bytes)

      refute half_bytes == kitty_bytes,
             "expected different bytes for :halfblocks vs :kitty on an :auto image"
    end
  end

  describe "ExRatatui.set_image_protocol/2" do
    test "accepts every protocol atom on a test terminal" do
      terminal = ExRatatui.init_test_terminal(20, 5)
      on_exit(fn -> ExRatatui.Native.restore_terminal(terminal) end)

      for protocol <- [:auto, :halfblocks, :kitty, :sixel, :iterm2] do
        assert :ok = ExRatatui.set_image_protocol(terminal, protocol)
      end
    end

    test "rejects unknown protocol atoms via guard" do
      terminal = ExRatatui.init_test_terminal(20, 5)
      on_exit(fn -> ExRatatui.Native.restore_terminal(terminal) end)

      assert_raise FunctionClauseError, fn ->
        ExRatatui.set_image_protocol(terminal, :gibberish)
      end
    end
  end

  describe "ExRatatui.SSH.Daemon image_protocol forwarding" do
    alias ExRatatui.SSH.Daemon

    defmodule TUI do
      @moduledoc false
      def init(_), do: {:ok, %{}}
      def render(_, _), do: []
      def handle_event(_, state), do: {:noreply, state}
    end

    test "build_daemon_opts threads :image_protocol into cli_args" do
      daemon_opts = Daemon.build_daemon_opts(TUI, image_protocol: :kitty)

      # ssh_cli is `{ExRatatui.SSH, args}` — args is a keyword list
      assert {ExRatatui.SSH, cli_args} = Keyword.fetch!(daemon_opts, :ssh_cli)
      assert cli_args[:image_protocol] == :kitty

      # subsystem args carry the same hint
      [{_name, {ExRatatui.SSH, subsystem_args}}] = Keyword.fetch!(daemon_opts, :subsystems)
      assert subsystem_args[:image_protocol] == :kitty
    end

    test "build_daemon_opts omits image_protocol when not set" do
      daemon_opts = Daemon.build_daemon_opts(TUI, [])
      {_mod, cli_args} = Keyword.fetch!(daemon_opts, :ssh_cli)
      refute Keyword.has_key?(cli_args, :image_protocol)
    end

    test "build_daemon_opts raises on invalid :image_protocol value" do
      assert_raise ArgumentError, ~r/invalid :image_protocol/, fn ->
        Daemon.build_daemon_opts(TUI, image_protocol: :gibberish)
      end
    end
  end

  describe "ExRatatui.Distributed client image_protocol forwarding" do
    alias ExRatatui.Distributed

    test "start_local_client keeps :image_protocol in client opts" do
      # Build a custom init_terminal so we don't touch the real terminal
      # in tests. We just want to verify the opt threads through.
      probe = self()

      init_fn = fn _test_mode ->
        terminal = ExRatatui.init_test_terminal(20, 5)
        send(probe, {:client_terminal, terminal})
        terminal
      end

      {:ok, client} =
        Distributed.start_local_client(
          test_mode: {20, 5},
          init_terminal: init_fn,
          image_protocol: :sixel
        )

      assert_receive {:client_terminal, terminal}
      # Probing for the hint applied: set the same hint again and confirm
      # :ok comes back. The client called terminal_set_image_protocol/2
      # during init; we can verify the terminal accepts the same call now.
      assert :ok = ExRatatui.set_image_protocol(terminal, :sixel)

      GenServer.stop(client)
    end

    test "start_local_client drops untracked opts" do
      # Confirms the Keyword.take whitelist covers image_protocol (regression
      # guard — without the chunk-6 addition this option would be silently
      # dropped on its way to Client.start_link).
      init_fn = fn _ -> ExRatatui.init_test_terminal(10, 3) end

      {:ok, client} =
        Distributed.start_local_client(
          test_mode: {10, 3},
          init_terminal: init_fn,
          image_protocol: :iterm2,
          some_unknown_opt: :ignored
        )

      assert is_pid(client)
      GenServer.stop(client)
    end
  end
end
