defmodule ExRatatui.Property.EventDecodePropertyTest do
  @moduledoc """
  Property-based invariants for `ExRatatui.decode_event/1`, the boundary
  between raw NIF tuples and the `ExRatatui.Event.*` structs exposed to
  apps. Invariants checked:

    * every shape the NIF can return decodes into exactly one event struct
    * all fields round-trip into the struct unchanged
    * the decoder is total — `nil` and `{:error, _}` pass through
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ExRatatui.Event.{Key, Mouse, Paste, Resize}

  @key_codes ~w(
    a b c q z 1 5 9 space enter esc tab back_tab backspace delete insert
    up down left right home end page_up page_down
    f1 f2 f3 f12 caps_lock scroll_lock num_lock print_screen pause menu
    keypad_begin
  )

  @modifiers ~w(shift ctrl alt super hyper meta)

  @mouse_kinds ~w(down up drag moved scroll_up scroll_down scroll_left scroll_right)

  @mouse_buttons ~w(left right middle)

  defp modifiers_gen do
    gen all(mods <- list_of(member_of(@modifiers), max_length: 6)) do
      Enum.uniq(mods)
    end
  end

  defp key_tuple_gen do
    gen all(
          code <- member_of(@key_codes),
          modifiers <- modifiers_gen(),
          kind <- member_of(~w(press release repeat))
        ) do
      {:key, code, modifiers, kind}
    end
  end

  defp mouse_tuple_gen do
    gen all(
          kind <- member_of(@mouse_kinds),
          button <- one_of([constant(nil), member_of(@mouse_buttons)]),
          x <- integer(0..1000),
          y <- integer(0..1000),
          modifiers <- modifiers_gen()
        ) do
      {:mouse, kind, button, x, y, modifiers}
    end
  end

  defp resize_tuple_gen do
    gen all(
          width <- integer(1..10_000),
          height <- integer(1..10_000)
        ) do
      {:resize, width, height}
    end
  end

  defp paste_tuple_gen do
    gen all(content <- string(:printable, max_length: 64)) do
      {:paste, content}
    end
  end

  property "decode_event/1 on a :key tuple yields an Event.Key with all fields preserved" do
    check all({:key, code, mods, kind} = raw <- key_tuple_gen()) do
      assert %Key{code: ^code, modifiers: ^mods, kind: ^kind} =
               ExRatatui.decode_event(raw)
    end
  end

  property "decode_event/1 on a :mouse tuple yields an Event.Mouse with all fields preserved" do
    check all({:mouse, kind, button, x, y, mods} = raw <- mouse_tuple_gen()) do
      assert %Mouse{kind: ^kind, button: ^button, x: ^x, y: ^y, modifiers: ^mods} =
               ExRatatui.decode_event(raw)
    end
  end

  property "decode_event/1 on a :resize tuple yields an Event.Resize with all fields preserved" do
    check all({:resize, w, h} = raw <- resize_tuple_gen()) do
      assert %Resize{width: ^w, height: ^h} = ExRatatui.decode_event(raw)
    end
  end

  property "decode_event/1 on a :paste tuple yields an Event.Paste with content preserved" do
    check all({:paste, content} = raw <- paste_tuple_gen()) do
      assert %Paste{content: ^content} = ExRatatui.decode_event(raw)
    end
  end

  test "decode_event/1 passes nil through" do
    assert ExRatatui.decode_event(nil) == nil
  end

  property "decode_event/1 passes {:error, reason} through" do
    check all(reason <- one_of([atom(:alphanumeric), binary()])) do
      assert ExRatatui.decode_event({:error, reason}) == {:error, reason}
    end
  end
end
