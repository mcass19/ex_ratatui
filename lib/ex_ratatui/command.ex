defmodule ExRatatui.Command do
  @moduledoc """
  Commands represent one-shot side effects scheduled by an `ExRatatui.App`.

  They are produced from reducer updates and executed by the ExRatatui server runtime
  after the new state has been committed and rendered.

  Available command constructors:

    * `message/1` — send an immediate self-message to the app process
    * `send_after/2` — schedule a delayed self-message
    * `async/2` — run a zero-arity function in the background and map the result
      back into an app message
    * `batch/1` — group multiple commands into one return value

  Reducer callbacks can return commands from `init/1` or `update/2` via
  `commands: [...]`.
  """

  @enforce_keys [:kind]
  defstruct [:kind, :message, :delay_ms, :fun, :mapper, :commands]

  @type async_fun :: (-> term())
  @type async_mapper :: (term() -> term())

  @type t ::
          %__MODULE__{kind: :message, message: term()}
          | %__MODULE__{kind: :after, delay_ms: non_neg_integer(), message: term()}
          | %__MODULE__{kind: :async, fun: async_fun(), mapper: async_mapper()}
          | %__MODULE__{kind: :batch, commands: [t()]}

  @spec none() :: []
  def none, do: []

  @spec message(term()) :: t()
  def message(message), do: %__MODULE__{kind: :message, message: message}

  @spec send_after(non_neg_integer(), term()) :: t()
  def send_after(delay_ms, message) when is_integer(delay_ms) and delay_ms >= 0 do
    %__MODULE__{kind: :after, delay_ms: delay_ms, message: message}
  end

  @spec async(async_fun(), async_mapper()) :: t()
  def async(fun, mapper) when is_function(fun, 0) and is_function(mapper, 1) do
    %__MODULE__{kind: :async, fun: fun, mapper: mapper}
  end

  @spec batch([t()]) :: t()
  def batch(commands) when is_list(commands), do: %__MODULE__{kind: :batch, commands: commands}

  @doc false
  @spec normalize(term()) :: [t()]
  def normalize(nil), do: []
  def normalize([]), do: []
  def normalize(%__MODULE__{kind: :batch, commands: commands}), do: normalize(commands)
  def normalize(%__MODULE__{} = command), do: [command]

  def normalize(commands) when is_list(commands) do
    Enum.flat_map(commands, &normalize/1)
  end

  def normalize(other) do
    raise ArgumentError, "unsupported ExRatatui command: #{inspect(other)}"
  end
end
