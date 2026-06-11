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

  @doc """
  Returns an empty subscription list.

  Useful when `subscriptions/1` or helper functions want to return an explicit
  "no subscriptions" value.

  ## Examples

      iex> ExRatatui.Subscription.none()
      []
  """
  @spec none() :: []
  def none, do: []

  @doc """
  Declares a repeating self-message subscription.

  `id` should be stable across renders for the same logical subscription so the
  runtime can keep it armed instead of cancelling and recreating it.

  ## Examples

      iex> ExRatatui.Subscription.interval(:tick, 1000, :refresh)
      %ExRatatui.Subscription{id: :tick, kind: :interval, interval_ms: 1000, message: :refresh}
  """
  @spec interval(term(), pos_integer(), term()) :: t()
  def interval(id, interval_ms, message)
      when is_integer(interval_ms) and interval_ms > 0 do
    %__MODULE__{id: id, kind: :interval, interval_ms: interval_ms, message: message}
  end

  @doc """
  Declares a one-shot self-message subscription.

  Like `interval/3`, `id` is used for reconciliation. Once the message fires,
  the subscription stays inactive until the app returns it again.

  ## Examples

      iex> ExRatatui.Subscription.once(:boot, 50, :ready)
      %ExRatatui.Subscription{id: :boot, kind: :once, interval_ms: 50, message: :ready}
  """
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
