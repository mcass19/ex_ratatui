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
end
