defmodule ExRatatui.Subscription do
  @moduledoc """
  Subscriptions represent ongoing or delayed self-messages owned by an app.

  The server reconciles subscriptions after each state transition, diffing by
  stable `id` so applications can declare timers without manually managing
  `Process.send_after/3` references.

  Available subscription constructors:

    * `interval/3` — repeated self-message at a fixed interval
    * `once/3` — one-shot self-message delivered once after a delay

  Reducer apps declare subscriptions by implementing `subscriptions/1`.
  """

  @enforce_keys [:id, :kind, :interval_ms, :message]
  defstruct [:id, :kind, :interval_ms, :message]

  @type kind :: :interval | :once

  @type t :: %__MODULE__{
          id: term(),
          kind: kind(),
          interval_ms: pos_integer(),
          message: term()
        }

  @spec none() :: []
  def none, do: []

  @spec interval(term(), pos_integer(), term()) :: t()
  def interval(id, interval_ms, message)
      when is_integer(interval_ms) and interval_ms > 0 do
    %__MODULE__{id: id, kind: :interval, interval_ms: interval_ms, message: message}
  end

  @spec once(term(), pos_integer(), term()) :: t()
  def once(id, interval_ms, message)
      when is_integer(interval_ms) and interval_ms > 0 do
    %__MODULE__{id: id, kind: :once, interval_ms: interval_ms, message: message}
  end

  @doc false
  @spec normalize(term()) :: [t()]
  def normalize(nil), do: []
  def normalize([]), do: []
  def normalize(%__MODULE__{} = subscription), do: [subscription]

  def normalize(subscriptions) when is_list(subscriptions) do
    Enum.flat_map(subscriptions, &normalize/1)
  end

  def normalize(other) do
    raise ArgumentError, "unsupported ExRatatui subscription: #{inspect(other)}"
  end
end
