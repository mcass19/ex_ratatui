defmodule ExRatatui.Widgets.TextInputTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Layout.Rect
  alias ExRatatui.Native
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, TextInput}

  setup do
    terminal = ExRatatui.init_test_terminal(60, 15)
    on_exit(fn -> Native.restore_terminal(terminal) end)
    %{terminal: terminal}
  end

  describe "TextInput widget" do
    test "renders text input with value", %{terminal: terminal} do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_handle_key(state, "h")
      ExRatatui.text_input_handle_key(state, "e")
      ExRatatui.text_input_handle_key(state, "l")
      ExRatatui.text_input_handle_key(state, "l")
      ExRatatui.text_input_handle_key(state, "o")

      input = %TextInput{
        state: state,
        style: %Style{fg: :white},
        cursor_style: %Style{fg: :black, bg: :white}
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 1}

      assert :ok = ExRatatui.draw(terminal, [{input, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "hello"
    end

    test "renders placeholder when empty", %{terminal: terminal} do
      state = ExRatatui.text_input_new()

      input = %TextInput{
        state: state,
        placeholder: "Type here...",
        placeholder_style: %Style{fg: :dark_gray},
        cursor_style: %Style{fg: :black, bg: :white}
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 1}

      assert :ok = ExRatatui.draw(terminal, [{input, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Type here..."
    end

    test "renders with block", %{terminal: terminal} do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_set_value(state, "test value")

      input = %TextInput{
        state: state,
        style: %Style{fg: :white},
        cursor_style: %Style{fg: :black, bg: :white},
        block: %Block{title: "Search", borders: [:all], border_type: :rounded}
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 3}

      assert :ok = ExRatatui.draw(terminal, [{input, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Search"
      assert content =~ "test value"
    end

    test "text_input struct has correct defaults" do
      input = %TextInput{}
      assert input.state == nil
      assert input.placeholder == nil
      assert input.block == nil
      assert input.style == %Style{}
      assert input.cursor_style == %Style{}
      assert input.placeholder_style == %Style{}
    end
  end

  describe "TextInput state management" do
    test "new text input has empty value" do
      state = ExRatatui.text_input_new()
      assert ExRatatui.text_input_get_value(state) == ""
    end

    test "typing characters builds up value" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_handle_key(state, "a")
      ExRatatui.text_input_handle_key(state, "b")
      ExRatatui.text_input_handle_key(state, "c")
      assert ExRatatui.text_input_get_value(state) == "abc"
    end

    test "set_value replaces content" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_handle_key(state, "x")
      ExRatatui.text_input_set_value(state, "hello world")
      assert ExRatatui.text_input_get_value(state) == "hello world"
    end

    test "set_value to empty string clears input" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_set_value(state, "something")
      ExRatatui.text_input_set_value(state, "")
      assert ExRatatui.text_input_get_value(state) == ""
    end

    test "cursor starts at 0" do
      state = ExRatatui.text_input_new()
      assert ExRatatui.text_input_cursor(state) == 0
    end

    test "cursor advances with each character typed" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_handle_key(state, "a")
      ExRatatui.text_input_handle_key(state, "b")
      assert ExRatatui.text_input_cursor(state) == 2
    end

    test "backspace deletes character before cursor" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_set_value(state, "abc")
      ExRatatui.text_input_handle_key(state, "backspace")
      assert ExRatatui.text_input_get_value(state) == "ab"
    end

    test "backspace on empty input is a no-op" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_handle_key(state, "backspace")
      assert ExRatatui.text_input_get_value(state) == ""
      assert ExRatatui.text_input_cursor(state) == 0
    end

    test "delete removes character at cursor" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_set_value(state, "abc")
      # Move cursor to beginning
      ExRatatui.text_input_handle_key(state, "home")
      ExRatatui.text_input_handle_key(state, "delete")
      assert ExRatatui.text_input_get_value(state) == "bc"
    end

    test "left arrow moves cursor back" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_set_value(state, "abc")
      # Cursor is at end (3)
      ExRatatui.text_input_handle_key(state, "left")
      assert ExRatatui.text_input_cursor(state) == 2
    end

    test "right arrow moves cursor forward" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_set_value(state, "abc")
      ExRatatui.text_input_handle_key(state, "home")
      ExRatatui.text_input_handle_key(state, "right")
      assert ExRatatui.text_input_cursor(state) == 1
    end

    test "home moves cursor to beginning" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_set_value(state, "hello")
      ExRatatui.text_input_handle_key(state, "home")
      assert ExRatatui.text_input_cursor(state) == 0
    end

    test "end moves cursor to end" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_set_value(state, "hello")
      ExRatatui.text_input_handle_key(state, "home")
      ExRatatui.text_input_handle_key(state, "end")
      assert ExRatatui.text_input_cursor(state) == 5
    end

    test "inserting in the middle of text" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_set_value(state, "ac")
      ExRatatui.text_input_handle_key(state, "home")
      ExRatatui.text_input_handle_key(state, "right")
      ExRatatui.text_input_handle_key(state, "b")
      assert ExRatatui.text_input_get_value(state) == "abc"
      assert ExRatatui.text_input_cursor(state) == 2
    end

    test "left at beginning is a no-op" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_set_value(state, "abc")
      ExRatatui.text_input_handle_key(state, "home")
      ExRatatui.text_input_handle_key(state, "left")
      assert ExRatatui.text_input_cursor(state) == 0
    end

    test "right at end is a no-op" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_set_value(state, "abc")
      ExRatatui.text_input_handle_key(state, "right")
      assert ExRatatui.text_input_cursor(state) == 3
    end

    test "insert_str appends at cursor" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_set_value(state, "hello")
      ExRatatui.text_input_insert_str(state, " world")
      assert ExRatatui.text_input_get_value(state) == "hello world"
      assert ExRatatui.text_input_cursor(state) == 11
    end

    test "insert_str inserts at cursor position" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_set_value(state, "ac")
      ExRatatui.text_input_handle_key(state, "home")
      ExRatatui.text_input_handle_key(state, "right")
      ExRatatui.text_input_insert_str(state, "BBB")
      assert ExRatatui.text_input_get_value(state) == "aBBBc"
      assert ExRatatui.text_input_cursor(state) == 4
    end

    test "insert_str strips newlines and other control characters" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_insert_str(state, "a\nb\rc\tde")
      assert ExRatatui.text_input_get_value(state) == "abcde"
      assert ExRatatui.text_input_cursor(state) == 5
    end

    test "insert_str all-control input is a no-op" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_set_value(state, "x")
      ExRatatui.text_input_insert_str(state, "\n\r\t")
      assert ExRatatui.text_input_get_value(state) == "x"
      assert ExRatatui.text_input_cursor(state) == 1
    end
  end
end
