defmodule ExRatatui.LocalInputTest do
  # async: false — these tests toggle the global :ex_ratatui app env that
  # gates the handoff, so they must not run alongside one another.
  use ExUnit.Case, async: false

  alias ExRatatui.LocalInput

  # Mirrors the relevant branches of prim_tty:reader_loop/2: ack a disable,
  # block until enable, ack that, and loop. Lets us drive the real handoff
  # protocol without parking the suite's actual :user_drv_reader.
  defp spawn_fake_reader do
    spawn_link(fn -> fake_reader_loop() end)
  end

  defp fake_reader_loop do
    receive do
      {disable_alias, :disable} ->
        send(disable_alias, {disable_alias, :ok})

        receive do
          {enable_alias, :enable} ->
            send(enable_alias, {enable_alias, :ok})
            fake_reader_loop()
        end
    end
  end

  describe "detach/1 and reattach/1" do
    test "parks a registered reader and resumes it on reattach" do
      reader = spawn_fake_reader()
      Process.register(reader, :ex_ratatui_test_reader)

      assert {:detached, ^reader} = handle = LocalInput.detach(:ex_ratatui_test_reader)
      assert Process.alive?(reader)

      assert :ok = LocalInput.reattach(handle)
      assert Process.alive?(reader)
    end

    test "is a no-op when the reader name is not registered" do
      assert LocalInput.detach(:ex_ratatui_unregistered_reader) == :not_detached
    end

    test "is a no-op when the reader process is already dead" do
      {pid, ref} = spawn_monitor(fn -> :ok end)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}

      assert LocalInput.detach(pid) == :not_detached
    end

    test "is a no-op when the reader never acknowledges" do
      deaf = spawn_link(fn -> Process.sleep(:infinity) end)

      Application.put_env(:ex_ratatui, :local_input_timeout, 50)
      on_exit(fn -> Application.delete_env(:ex_ratatui, :local_input_timeout) end)

      assert LocalInput.detach(deaf) == :not_detached
    end

    test "reattach/1 on a no-op handle does nothing" do
      assert LocalInput.reattach(:not_detached) == :ok
    end
  end

  describe "detach/0 app-env gate" do
    test "is a no-op when detaching is disabled (suite default)" do
      assert LocalInput.detach() == :not_detached
    end

    test "consults the configured reader name when enabled" do
      Application.put_env(:ex_ratatui, :detach_local_input, true)
      Application.put_env(:ex_ratatui, :local_input_reader, :ex_ratatui_no_such_reader)

      on_exit(fn ->
        Application.put_env(:ex_ratatui, :detach_local_input, false)
        Application.delete_env(:ex_ratatui, :local_input_reader)
      end)

      # Enabled, but the configured reader is unregistered → still a no-op.
      assert LocalInput.detach() == :not_detached
    end
  end
end
