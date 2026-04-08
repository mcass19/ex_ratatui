defmodule ExRatatui.SessionTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Native

  describe "session_new/2" do
    test "returns a reference for reasonable dimensions" do
      ref = Native.session_new(80, 24)
      assert is_reference(ref)
      assert :ok = Native.session_close(ref)
    end

    test "succeeds at a 1x1 minimum size" do
      ref = Native.session_new(1, 1)
      assert is_reference(ref)
      assert :ok = Native.session_close(ref)
    end

    test "independent sessions get distinct references" do
      a = Native.session_new(80, 24)
      b = Native.session_new(80, 24)

      assert is_reference(a)
      assert is_reference(b)
      assert a != b

      assert :ok = Native.session_close(a)
      assert :ok = Native.session_close(b)
    end
  end

  describe "session_close/1" do
    test "is idempotent" do
      ref = Native.session_new(80, 24)
      assert :ok = Native.session_close(ref)
      assert :ok = Native.session_close(ref)
    end

    test "does not touch OS terminal state" do
      # The whole point of the session abstraction: creating and closing
      # sessions in a test context must not enable raw mode, enter the alt
      # screen, or otherwise touch the real tty. If any of that happened,
      # async test runs would be breaking each other and the user's shell.
      for _ <- 1..8 do
        ref = Native.session_new(80, 24)
        assert :ok = Native.session_close(ref)
      end
    end
  end

  describe "session_draw/2 and session_take_output/1" do
    test "draw with empty commands still emits a frame into the writer" do
      ref = Native.session_new(20, 5)

      assert :ok = Native.session_draw(ref, [])
      output = Native.session_take_output(ref)

      assert is_binary(output)

      assert byte_size(output) > 0,
             "expected ratatui's frame setup ANSI to land in the writer"

      assert :ok = Native.session_close(ref)
    end

    test "draw with a Clear widget round-trips through decoding" do
      ref = Native.session_new(20, 5)

      commands = [{%{"type" => "clear"}, %{"x" => 0, "y" => 0, "width" => 20, "height" => 5}}]
      assert :ok = Native.session_draw(ref, commands)

      assert byte_size(Native.session_take_output(ref)) > 0
      assert :ok = Native.session_close(ref)
    end

    test "session_take_output drains the buffer between draws" do
      ref = Native.session_new(20, 5)

      :ok = Native.session_draw(ref, [])
      first = Native.session_take_output(ref)
      assert byte_size(first) > 0

      # Second drain with no intervening writes is empty.
      assert <<>> = Native.session_take_output(ref)

      :ok = Native.session_draw(ref, [])
      second = Native.session_take_output(ref)
      assert byte_size(second) > 0

      assert :ok = Native.session_close(ref)
    end

    test "draw rejects an unknown widget type" do
      ref = Native.session_new(20, 5)

      commands = [
        {%{"type" => "not_a_widget"}, %{"x" => 0, "y" => 0, "width" => 5, "height" => 1}}
      ]

      assert {:error, _reason} = Native.session_draw(ref, commands)

      assert :ok = Native.session_close(ref)
    end

    test "draw on a closed session returns an error" do
      ref = Native.session_new(20, 5)
      :ok = Native.session_close(ref)

      assert {:error, reason} = Native.session_draw(ref, [])
      assert is_binary(reason) or is_bitstring(reason)
      assert reason =~ "closed"
    end

    test "concurrent sessions render into independent buffers" do
      a = Native.session_new(20, 5)
      b = Native.session_new(20, 5)

      :ok = Native.session_draw(a, [])
      # b has not been drawn yet — its buffer must be empty.
      assert <<>> = Native.session_take_output(b)
      assert byte_size(Native.session_take_output(a)) > 0

      :ok = Native.session_close(a)
      :ok = Native.session_close(b)
    end
  end

  describe "session_feed_input/2" do
    test "parses a plain ASCII keystroke into a key event" do
      ref = Native.session_new(20, 5)

      assert [{:key, "a", [], "press"}] = Native.session_feed_input(ref, "a")

      assert :ok = Native.session_close(ref)
    end

    test "parses Ctrl+letter from a C0 control byte" do
      ref = Native.session_new(20, 5)

      # 0x03 is Ctrl+C.
      assert [{:key, "c", ["ctrl"], "press"}] = Native.session_feed_input(ref, <<0x03>>)

      assert :ok = Native.session_close(ref)
    end

    test "parses named control keys with their friendly names" do
      ref = Native.session_new(20, 5)

      assert [{:key, "enter", [], "press"}] = Native.session_feed_input(ref, "\n")
      assert [{:key, "tab", [], "press"}] = Native.session_feed_input(ref, "\t")
      assert [{:key, "backspace", [], "press"}] = Native.session_feed_input(ref, <<0x7F>>)

      assert :ok = Native.session_close(ref)
    end

    test "parses CSI arrow keys" do
      ref = Native.session_new(20, 5)

      assert [{:key, "up", [], "press"}] = Native.session_feed_input(ref, "\e[A")
      assert [{:key, "down", [], "press"}] = Native.session_feed_input(ref, "\e[B")
      assert [{:key, "right", [], "press"}] = Native.session_feed_input(ref, "\e[C")
      assert [{:key, "left", [], "press"}] = Native.session_feed_input(ref, "\e[D")

      assert :ok = Native.session_close(ref)
    end

    test "parses CSI sequences with modifiers" do
      ref = Native.session_new(20, 5)

      # CSI 1 ; 5 A — Ctrl+Up.
      assert [{:key, "up", ["ctrl"], "press"}] = Native.session_feed_input(ref, "\e[1;5A")

      assert :ok = Native.session_close(ref)
    end

    test "parses SS3 function keys" do
      ref = Native.session_new(20, 5)

      assert [{:key, "f1", [], "press"}] = Native.session_feed_input(ref, "\eOP")
      assert [{:key, "f2", [], "press"}] = Native.session_feed_input(ref, "\eOQ")

      assert :ok = Native.session_close(ref)
    end

    test "parses tilde-terminated keys (delete, page_up, F-keys)" do
      ref = Native.session_new(20, 5)

      assert [{:key, "delete", [], "press"}] = Native.session_feed_input(ref, "\e[3~")
      assert [{:key, "page_up", [], "press"}] = Native.session_feed_input(ref, "\e[5~")
      assert [{:key, "f12", [], "press"}] = Native.session_feed_input(ref, "\e[24~")

      assert :ok = Native.session_close(ref)
    end

    test "buffers a partial escape sequence across calls" do
      # The whole reason the parser owns a vte::Parser instead of being
      # stateless: SSH (and any other byte-stream transport) may chunk
      # an arrow-key press across two channel-data frames. The parser
      # must hold the half-sequence and only flush when it completes.
      ref = Native.session_new(20, 5)

      assert [] = Native.session_feed_input(ref, "\e")
      assert [] = Native.session_feed_input(ref, "[")
      assert [{:key, "up", [], "press"}] = Native.session_feed_input(ref, "A")

      assert :ok = Native.session_close(ref)
    end

    test "parses Alt+letter from ESC + letter" do
      ref = Native.session_new(20, 5)

      assert [{:key, "a", ["alt"], "press"}] = Native.session_feed_input(ref, "\ea")

      assert :ok = Native.session_close(ref)
    end

    test "empty input produces no events" do
      ref = Native.session_new(20, 5)

      assert [] = Native.session_feed_input(ref, "")

      assert :ok = Native.session_close(ref)
    end

    test "parses mixed text and a control in one feed" do
      ref = Native.session_new(20, 5)

      assert [
               {:key, "h", [], "press"},
               {:key, "i", [], "press"},
               {:key, "enter", [], "press"}
             ] = Native.session_feed_input(ref, "hi\n")

      assert :ok = Native.session_close(ref)
    end

    test "still parses input after the session has been closed" do
      # Closing the session drops the rendering terminal but the input
      # parser stays alive — a transport may want to drain trailing input
      # bytes after deciding to tear down rendering.
      ref = Native.session_new(20, 5)
      :ok = Native.session_close(ref)

      assert [{:key, "a", [], "press"}] = Native.session_feed_input(ref, "a")
    end

    test "concurrent sessions parse independently" do
      a = Native.session_new(20, 5)
      b = Native.session_new(20, 5)

      # Drive a partial CSI on `a` and ensure it doesn't bleed into `b`.
      assert [] = Native.session_feed_input(a, "\e[")
      assert [{:key, "x", [], "press"}] = Native.session_feed_input(b, "x")
      assert [{:key, "up", [], "press"}] = Native.session_feed_input(a, "A")

      :ok = Native.session_close(a)
      :ok = Native.session_close(b)
    end
  end

  describe "session_resize/3 and session_size/1" do
    test "session_size returns the dimensions session_new was created with" do
      ref = Native.session_new(80, 24)

      assert {80, 24} = Native.session_size(ref)

      assert :ok = Native.session_close(ref)
    end

    test "session_resize updates the size session_size returns" do
      ref = Native.session_new(20, 5)

      assert :ok = Native.session_resize(ref, 100, 30)
      assert {100, 30} = Native.session_size(ref)

      assert :ok = Native.session_close(ref)
    end

    test "session_resize lets subsequent draws render at the new size" do
      ref = Native.session_new(20, 5)

      :ok = Native.session_resize(ref, 40, 10)
      :ok = Native.session_draw(ref, [])

      assert byte_size(Native.session_take_output(ref)) > 0

      assert :ok = Native.session_close(ref)
    end

    test "session_resize on a closed session returns an error" do
      ref = Native.session_new(20, 5)
      :ok = Native.session_close(ref)

      assert {:error, reason} = Native.session_resize(ref, 40, 10)
      assert reason =~ "closed"
    end

    test "concurrent sessions resize independently" do
      a = Native.session_new(20, 5)
      b = Native.session_new(20, 5)

      :ok = Native.session_resize(a, 100, 30)
      assert {100, 30} = Native.session_size(a)
      # b stays at its original size — resize on a must not bleed across.
      assert {20, 5} = Native.session_size(b)

      :ok = Native.session_close(a)
      :ok = Native.session_close(b)
    end
  end

  describe "BEAM scheduler safety" do
    test "session_new does not block concurrent tasks" do
      tasks =
        for _ <- 1..4 do
          Task.async(fn ->
            Process.sleep(10)
            :alive
          end)
        end

      ref = Native.session_new(80, 24)
      assert is_reference(ref)
      assert :ok = Native.session_close(ref)

      results = Task.await_many(tasks, 5000)
      assert Enum.all?(results, &(&1 == :alive))
    end
  end

  describe "ExRatatui.Session (Elixir wrapper)" do
    alias ExRatatui.Event
    alias ExRatatui.Layout.Rect
    alias ExRatatui.Session
    alias ExRatatui.Widgets.Paragraph

    test "new/2 returns a Session struct holding a reference" do
      session = Session.new(80, 24)

      assert %Session{ref: ref} = session
      assert is_reference(ref)
      assert {80, 24} = Session.size(session)

      :ok = Session.close(session)
    end

    test "draw/2 encodes widget structs and renders into the in-memory buffer" do
      session = Session.new(20, 5)

      widgets = [{%Paragraph{text: "hi"}, %Rect{x: 0, y: 0, width: 20, height: 5}}]
      assert :ok = Session.draw(session, widgets)
      assert byte_size(Session.take_output(session)) > 0

      :ok = Session.close(session)
    end

    test "take_output/1 drains and returns an empty binary on second call" do
      session = Session.new(20, 5)

      :ok = Session.draw(session, [])
      first = Session.take_output(session)
      assert byte_size(first) > 0
      assert "" == Session.take_output(session)

      :ok = Session.close(session)
    end

    test "feed_input/2 returns decoded Event.Key structs" do
      session = Session.new(20, 5)

      assert [%Event.Key{code: "a", modifiers: [], kind: "press"}] =
               Session.feed_input(session, "a")

      :ok = Session.close(session)
    end

    test "feed_input/2 buffers a partial CSI across calls" do
      # Same guarantee the underlying NIF makes — exposed through the
      # Elixir wrapper so a transport can rely on it.
      session = Session.new(20, 5)

      assert [] = Session.feed_input(session, "\e")
      assert [] = Session.feed_input(session, "[")

      assert [%Event.Key{code: "up", modifiers: [], kind: "press"}] =
               Session.feed_input(session, "A")

      :ok = Session.close(session)
    end

    test "feed_input/2 still works after close/1" do
      # The input parser outlives the rendering terminal so a transport
      # can drain trailing input bytes after deciding to tear down rendering.
      session = Session.new(20, 5)
      :ok = Session.close(session)

      assert [%Event.Key{code: "x"}] = Session.feed_input(session, "x")
    end

    test "resize/3 updates the cached size" do
      session = Session.new(20, 5)

      assert :ok = Session.resize(session, 100, 30)
      assert {100, 30} = Session.size(session)

      :ok = Session.close(session)
    end

    test "draw/2 on a closed session returns an error tuple" do
      session = Session.new(20, 5)
      :ok = Session.close(session)

      assert {:error, reason} = Session.draw(session, [])
      assert reason =~ "closed"
    end

    test "resize/3 on a closed session returns an error tuple" do
      session = Session.new(20, 5)
      :ok = Session.close(session)

      assert {:error, reason} = Session.resize(session, 40, 10)
      assert reason =~ "closed"
    end

    test "close/1 is idempotent" do
      session = Session.new(20, 5)
      assert :ok = Session.close(session)
      assert :ok = Session.close(session)
    end

    test "concurrent sessions are independent" do
      a = Session.new(20, 5)
      b = Session.new(20, 5)

      :ok = Session.draw(a, [])
      assert "" == Session.take_output(b)
      assert byte_size(Session.take_output(a)) > 0

      :ok = Session.resize(a, 100, 30)
      assert {100, 30} = Session.size(a)
      assert {20, 5} = Session.size(b)

      :ok = Session.close(a)
      :ok = Session.close(b)
    end
  end
end
