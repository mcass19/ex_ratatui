defmodule ExRatatui.CommandTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Command

  test "constructors and normalize support every command shape" do
    message = Command.message(:boot)
    delayed = Command.send_after(10, :later)
    async_command = Command.async(fn -> :ok end, &{:done, &1})
    batch = Command.batch([message, delayed])

    assert Command.none() == []
    assert delayed == %Command{kind: :after, delay_ms: 10, message: :later}
    assert batch == %Command{kind: :batch, commands: [message, delayed]}
    assert Command.normalize(nil) == []
    assert Command.normalize([]) == []
    assert Command.normalize(message) == [message]
    assert Command.normalize(batch) == [message, delayed]
    assert Command.normalize([message, async_command]) == [message, async_command]
  end

  test "normalize raises on unsupported command terms" do
    assert_raise ArgumentError, "unsupported ExRatatui command: :bad", fn ->
      Command.normalize(:bad)
    end
  end
end
