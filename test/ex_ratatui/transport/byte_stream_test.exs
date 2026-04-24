defmodule ExRatatui.Transport.ByteStreamTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Event
  alias ExRatatui.Session
  alias ExRatatui.Transport.ByteStream

  describe "forward_input/3" do
    test "decodes key bytes and forwards them as :ex_ratatui_event" do
      session = Session.new(80, 24)

      events = ByteStream.forward_input(session, self(), "a")

      assert [%Event.Key{code: "a"}] = events
      assert_receive {:ex_ratatui_event, %Event.Key{code: "a"}}

      Session.close(session)
    end

    test "returns [] when the parser is mid-sequence (e.g. bare Esc)" do
      session = Session.new(80, 24)

      assert [] = ByteStream.forward_input(session, self(), <<0x1B>>)
      refute_receive {:ex_ratatui_event, _}
      refute_receive {:ex_ratatui_resize, _, _}

      Session.close(session)
    end

    test "absorbs Resize events: session is resized and :ex_ratatui_resize is sent" do
      session = Session.new(80, 24)

      # A Cursor Position Report `ESC[row;colR` is what the Session
      # parser actually lowers to an Event.Resize (the SSH subsystem
      # relies on it to discover the initial pty size). row=50
      # col=132 → Event.Resize{width: 132, height: 50}.
      bytes = "\e[50;132R"
      events = ByteStream.forward_input(session, self(), bytes)

      assert [%Event.Resize{width: 132, height: 50}] = events
      assert_receive {:ex_ratatui_resize, 132, 50}
      refute_receive {:ex_ratatui_event, %Event.Resize{}}
      assert Session.size(session) == {132, 50}

      Session.close(session)
    end

    test "dispatches a mix of events in order" do
      session = Session.new(80, 24)

      events = ByteStream.forward_input(session, self(), "ab")

      assert [%Event.Key{code: "a"}, %Event.Key{code: "b"}] = events
      assert_receive {:ex_ratatui_event, %Event.Key{code: "a"}}
      assert_receive {:ex_ratatui_event, %Event.Key{code: "b"}}

      Session.close(session)
    end
  end

  describe "forward_resize/4" do
    test "resizes the session and notifies the server" do
      session = Session.new(80, 24)

      assert :ok = ByteStream.forward_resize(session, self(), 100, 40)

      assert Session.size(session) == {100, 40}
      assert_receive {:ex_ratatui_resize, 100, 40}

      Session.close(session)
    end

    test "raises on non-positive dimensions" do
      session = Session.new(80, 24)

      assert_raise FunctionClauseError, fn ->
        ByteStream.forward_resize(session, self(), 0, 24)
      end

      assert_raise FunctionClauseError, fn ->
        ByteStream.forward_resize(session, self(), 80, -1)
      end

      Session.close(session)
    end
  end
end
