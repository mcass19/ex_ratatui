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
