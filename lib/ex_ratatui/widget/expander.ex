defmodule ExRatatui.Widget.Expander do
  @moduledoc false

  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widget

  @max_depth 32

  # The protocol's typespec promises a list return, but user impls can
  # still return garbage at runtime — keep the defensive clause even
  # though dialyzer sees it as unreachable.
  @dialyzer {:nowarn_function, validate!: 2}

  @doc false
  @spec expand!([{struct(), Rect.t()}]) :: [{struct(), Rect.t()}]
  def expand!(commands) when is_list(commands) do
    Enum.flat_map(commands, &expand_one!(&1, 0, []))
  end

  defp expand_one!({widget, %Rect{} = rect}, depth, path) when is_struct(widget) do
    case Widget.impl_for(widget) do
      nil ->
        [{widget, rect}]

      _impl ->
        check_depth!(depth, widget, path)

        children =
          widget
          |> Widget.render(rect)
          |> validate!(widget)

        new_path = [widget | path]
        Enum.flat_map(children, &expand_one!(&1, depth + 1, new_path))
    end
  end

  defp expand_one!(other, _depth, _path) do
    raise ArgumentError,
          "expected {widget, %ExRatatui.Layout.Rect{}}, got: #{inspect(other)}"
  end

  defp validate!(list, widget) when is_list(list) do
    Enum.each(list, fn
      {child, %Rect{}} when is_struct(child) -> :ok
      bad -> raise_invalid_return!(widget, bad)
    end)

    list
  end

  defp validate!(other, widget) do
    raise ArgumentError,
          "#{inspect(widget.__struct__)}.render/2 must return a list of " <>
            "{widget, %ExRatatui.Layout.Rect{}} tuples, got: #{inspect(other)}"
  end

  defp check_depth!(depth, widget, path) when depth >= @max_depth do
    chain =
      [widget | path]
      |> Enum.reverse()
      |> Enum.map_join(" -> ", &inspect(&1.__struct__))

    raise ArgumentError,
          "ExRatatui.Widget.render/2 exceeded max depth (#{@max_depth}): #{chain}"
  end

  defp check_depth!(_depth, _widget, _path), do: :ok

  defp raise_invalid_return!(widget, bad) do
    raise ArgumentError,
          "#{inspect(widget.__struct__)}.render/2 returned an invalid entry: #{inspect(bad)} " <>
            "(expected {widget, %ExRatatui.Layout.Rect{}})"
  end
end
