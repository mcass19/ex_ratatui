defmodule ExRatatui.TelemetryTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias ExRatatui.Runtime
  alias ExRatatui.Session
  alias ExRatatui.Telemetry
  alias ExRatatui.Test.ServerApps.Echo, as: TestApp

  # Attaches a self-forwarding handler for each event in `events` under a
  # unique id scoped to the test pid, and detaches on_exit.
  defp capture(events) do
    handler_id = "tel-test-#{inspect(self())}-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      events,
      &__MODULE__.__forward__/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  @doc false
  def __forward__(event, measurements, meta, test_pid) do
    send(test_pid, {:telemetry, event, measurements, meta})
  end

  describe "span/3" do
    test "prefixes the event with :ex_ratatui and emits start/stop" do
      capture([
        [:ex_ratatui, :sample, :op, :start],
        [:ex_ratatui, :sample, :op, :stop]
      ])

      result = Telemetry.span([:sample, :op], %{foo: :bar}, fn -> :result end)

      assert result == :result
      assert_receive {:telemetry, [:ex_ratatui, :sample, :op, :start], measurements, %{foo: :bar}}
      assert is_integer(measurements.system_time)
      assert_receive {:telemetry, [:ex_ratatui, :sample, :op, :stop], stop_meas, %{foo: :bar}}
      assert is_integer(stop_meas.duration) and stop_meas.duration >= 0
    end

    test "returns the fun's value unchanged, including tuple shapes" do
      capture([[:ex_ratatui, :sample, :op, :stop]])

      assert {:ok, %{count: 1}} ==
               Telemetry.span([:sample, :op], %{foo: :bar}, fn -> {:ok, %{count: 1}} end)

      assert_receive {:telemetry, [:ex_ratatui, :sample, :op, :stop], _, %{foo: :bar}}
    end

    test "emits exception on raise and re-raises" do
      capture([[:ex_ratatui, :sample, :op, :exception]])

      assert_raise RuntimeError, "boom", fn ->
        Telemetry.span([:sample, :op], %{}, fn -> raise "boom" end)
      end

      assert_receive {:telemetry, [:ex_ratatui, :sample, :op, :exception], _meas, meta}
      assert meta.kind == :error
      assert %RuntimeError{message: "boom"} = meta.reason
    end
  end

  describe "execute/3" do
    test "prefixes the event and adds system_time when missing" do
      capture([[:ex_ratatui, :some, :event]])

      Telemetry.execute([:some, :event], %{}, %{reason: :test})

      assert_receive {:telemetry, [:ex_ratatui, :some, :event], measurements, %{reason: :test}}
      assert is_integer(measurements.system_time)
    end

    test "does not overwrite a provided system_time" do
      capture([[:ex_ratatui, :some, :event]])

      Telemetry.execute([:some, :event], %{system_time: 42}, %{})

      assert_receive {:telemetry, [:ex_ratatui, :some, :event], %{system_time: 42}, _meta}
    end
  end

  describe "session lifecycle" do
    test "emits :open span on Session.new/2" do
      capture([
        [:ex_ratatui, :session, :lifecycle, :start],
        [:ex_ratatui, :session, :lifecycle, :stop]
      ])

      session = Session.new(10, 5)
      on_exit(fn -> Session.close(session) end)

      assert_receive {:telemetry, [:ex_ratatui, :session, :lifecycle, :start], _,
                      %{action: :open, width: 10, height: 5}}

      assert_receive {:telemetry, [:ex_ratatui, :session, :lifecycle, :stop], %{duration: _},
                      %{action: :open}}
    end

    test "emits :close span on Session.close/1" do
      capture([[:ex_ratatui, :session, :lifecycle, :stop]])

      session = Session.new(10, 5)
      :ok = Session.close(session)

      # drain the :open stop first
      assert_receive {:telemetry, [:ex_ratatui, :session, :lifecycle, :stop], _, %{action: :open}}

      assert_receive {:telemetry, [:ex_ratatui, :session, :lifecycle, :stop], _,
                      %{action: :close}}
    end
  end

  describe "server runtime spans" do
    test "emits transport :connect and runtime :init spans on start_link" do
      capture([
        [:ex_ratatui, :transport, :connect, :stop],
        [:ex_ratatui, :runtime, :init, :stop]
      ])

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: TestApp,
          name: nil,
          test_pid: self(),
          test_mode: {80, 24}
        )

      assert_receive {:telemetry, [:ex_ratatui, :transport, :connect, :stop], _,
                      %{mod: TestApp, transport: :local}}

      assert_receive {:telemetry, [:ex_ratatui, :runtime, :init, :stop], _,
                      %{mod: TestApp, transport: :local}}

      GenServer.stop(pid)
    end

    test "emits a render :frame span per render" do
      capture([[:ex_ratatui, :render, :frame, :stop]])

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: TestApp,
          name: nil,
          test_pid: self(),
          test_mode: {80, 24}
        )

      assert_receive {:telemetry, [:ex_ratatui, :render, :frame, :stop], _measurements,
                      %{mod: TestApp, transport: :local, widget_count: 1}}

      GenServer.stop(pid)
    end

    test "emits runtime :event span on terminal event dispatch" do
      capture([[:ex_ratatui, :runtime, :event, :stop]])

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: TestApp,
          name: nil,
          test_pid: self(),
          test_mode: {80, 24}
        )

      event = %ExRatatui.Event.Key{code: "a", modifiers: [], kind: "press"}
      Runtime.inject_event(pid, event)

      assert_receive {:telemetry, [:ex_ratatui, :runtime, :event, :stop], _,
                      %{mod: TestApp, transport: :local, event: ^event}}

      GenServer.stop(pid)
    end

    test "emits runtime :update span on info dispatch" do
      capture([[:ex_ratatui, :runtime, :update, :stop]])

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: TestApp,
          name: nil,
          test_pid: self(),
          test_mode: {80, 24}
        )

      send(pid, :ping)

      assert_receive {:telemetry, [:ex_ratatui, :runtime, :update, :stop], _,
                      %{mod: TestApp, transport: :local, msg: :ping}}

      GenServer.stop(pid)
    end

    test "emits transport :disconnect on terminate" do
      capture([[:ex_ratatui, :transport, :disconnect]])

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: TestApp,
          name: nil,
          test_pid: self(),
          test_mode: {80, 24}
        )

      GenServer.stop(pid)

      assert_receive {:telemetry, [:ex_ratatui, :transport, :disconnect], _measurements,
                      %{mod: TestApp, transport: :local, reason: :normal}}
    end
  end

  describe "attach_default_logger/1" do
    test "attaches and detaches cleanly" do
      assert :ok = Telemetry.attach_default_logger()
      assert {:error, :already_exists} = Telemetry.attach_default_logger()
      assert :ok = Telemetry.detach_default_logger()
      assert {:error, :not_found} = Telemetry.detach_default_logger()
    end

    test "logs event name, measurements, and metadata" do
      log =
        capture_log([level: :debug], fn ->
          :ok =
            Telemetry.attach_default_logger(
              level: :debug,
              events: [[:ex_ratatui, :render, :dropped]]
            )

          Telemetry.execute([:render, :dropped], %{bytes: 0}, %{reason: :because})
          Telemetry.detach_default_logger()
        end)

      assert log =~ "[ex_ratatui]"
      assert log =~ "ex_ratatui.render.dropped"
      assert log =~ "because"
    end
  end
end
