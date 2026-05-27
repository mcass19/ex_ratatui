defmodule ExRatatui.Widgets.TextareaTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Layout.Rect
  alias ExRatatui.Native
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, Textarea}

  setup do
    terminal = ExRatatui.init_test_terminal(60, 15)
    on_exit(fn -> Native.restore_terminal(terminal) end)
    %{terminal: terminal}
  end

  describe "Textarea widget" do
    test "renders textarea with value", %{terminal: terminal} do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_handle_key(state, "h", [])
      ExRatatui.textarea_handle_key(state, "e", [])
      ExRatatui.textarea_handle_key(state, "l", [])
      ExRatatui.textarea_handle_key(state, "l", [])
      ExRatatui.textarea_handle_key(state, "o", [])

      input = %Textarea{
        state: state,
        style: %Style{fg: :white},
        cursor_style: %Style{fg: :black, bg: :white}
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 5}

      assert :ok = ExRatatui.draw(terminal, [{input, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "hello"
    end

    test "renders placeholder when empty", %{terminal: terminal} do
      state = ExRatatui.textarea_new()

      input = %Textarea{
        state: state,
        placeholder: "Type a message...",
        placeholder_style: %Style{fg: :dark_gray},
        cursor_style: %Style{fg: :black, bg: :white}
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 5}

      assert :ok = ExRatatui.draw(terminal, [{input, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Type a message..."
    end

    test "renders with block", %{terminal: terminal} do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_set_value(state, "test value")

      input = %Textarea{
        state: state,
        style: %Style{fg: :white},
        cursor_style: %Style{fg: :black, bg: :white},
        block: %Block{title: "Message", borders: [:all], border_type: :rounded}
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 5}

      assert :ok = ExRatatui.draw(terminal, [{input, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Message"
      assert content =~ "test value"
    end

    test "textarea struct has correct defaults" do
      input = %Textarea{}
      assert input.state == nil
      assert input.placeholder == nil
      assert input.block == nil
      assert input.line_number_style == nil
      assert input.style == %Style{}
      assert input.cursor_style == %Style{}
    end
  end

  describe "Textarea state management" do
    test "new textarea has empty value" do
      state = ExRatatui.textarea_new()
      assert ExRatatui.textarea_get_value(state) == ""
    end

    test "handle_key with default modifiers (2-arity)" do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_handle_key(state, "a")
      ExRatatui.textarea_handle_key(state, "b")
      assert ExRatatui.textarea_get_value(state) == "ab"
    end

    test "typing characters builds up value" do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_handle_key(state, "a", [])
      ExRatatui.textarea_handle_key(state, "b", [])
      ExRatatui.textarea_handle_key(state, "c", [])
      assert ExRatatui.textarea_get_value(state) == "abc"
    end

    test "enter creates new line" do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_handle_key(state, "h", [])
      ExRatatui.textarea_handle_key(state, "i", [])
      ExRatatui.textarea_handle_key(state, "enter", [])
      ExRatatui.textarea_handle_key(state, "x", [])
      assert ExRatatui.textarea_get_value(state) == "hi\nx"
    end

    test "set_value replaces content" do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_handle_key(state, "x", [])
      ExRatatui.textarea_set_value(state, "line1\nline2")
      assert ExRatatui.textarea_get_value(state) == "line1\nline2"
    end

    test "set_value to empty clears textarea" do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_set_value(state, "something")
      ExRatatui.textarea_set_value(state, "")
      assert ExRatatui.textarea_get_value(state) == ""
    end

    test "cursor returns row and col" do
      state = ExRatatui.textarea_new()
      assert ExRatatui.textarea_cursor(state) == {0, 0}

      ExRatatui.textarea_handle_key(state, "a", [])
      ExRatatui.textarea_handle_key(state, "b", [])
      assert ExRatatui.textarea_cursor(state) == {0, 2}

      ExRatatui.textarea_handle_key(state, "enter", [])
      assert {1, 0} = ExRatatui.textarea_cursor(state)
    end

    test "line_count returns number of lines" do
      state = ExRatatui.textarea_new()
      assert ExRatatui.textarea_line_count(state) == 1

      ExRatatui.textarea_set_value(state, "a\nb\nc")
      assert ExRatatui.textarea_line_count(state) == 3
    end

    test "backspace at start of line merges with previous" do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_set_value(state, "hello\nworld")
      # Move to start of line 2 and backspace
      ExRatatui.textarea_handle_key(state, "down", [])
      ExRatatui.textarea_handle_key(state, "home", [])
      ExRatatui.textarea_handle_key(state, "backspace", [])
      assert ExRatatui.textarea_get_value(state) == "helloworld"
    end

    test "cursor up/down navigation" do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_set_value(state, "abc\ndef")
      # Cursor starts at (0, 0) after set_value
      ExRatatui.textarea_handle_key(state, "down", [])
      {row, _col} = ExRatatui.textarea_cursor(state)
      assert row == 1
      ExRatatui.textarea_handle_key(state, "up", [])
      {row, _col} = ExRatatui.textarea_cursor(state)
      assert row == 0
    end

    test "handle_key with modifiers" do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_handle_key(state, "a", [])
      ExRatatui.textarea_handle_key(state, "b", [])
      # Ctrl+A (Emacs: beginning of line)
      ExRatatui.textarea_handle_key(state, "a", ["ctrl"])
      {_row, col} = ExRatatui.textarea_cursor(state)
      assert col == 0
    end

    test "delete key removes character at cursor" do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_set_value(state, "abcd")
      # Move to beginning
      ExRatatui.textarea_handle_key(state, "home", [])
      # Delete char at cursor (removes 'a')
      ExRatatui.textarea_handle_key(state, "delete", [])
      assert ExRatatui.textarea_get_value(state) == "bcd"
    end

    test "Ctrl+K deletes to end of line" do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_set_value(state, "hello world")
      # Move to beginning, then right 5 times to position after "hello"
      ExRatatui.textarea_handle_key(state, "home", [])

      for _ <- 1..5 do
        ExRatatui.textarea_handle_key(state, "right", [])
      end

      # Ctrl+K should delete from cursor to end of line
      ExRatatui.textarea_handle_key(state, "k", ["ctrl"])
      assert ExRatatui.textarea_get_value(state) == "hello"
    end

    test "Ctrl+W deletes word backward" do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_set_value(state, "hello world")
      # Move to end
      ExRatatui.textarea_handle_key(state, "end", [])
      # Ctrl+W should delete "world"
      ExRatatui.textarea_handle_key(state, "w", ["ctrl"])
      value = ExRatatui.textarea_get_value(state)
      assert value == "hello "
    end

    test "Ctrl+E moves cursor to end of line" do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_set_value(state, "hello")
      # Move to beginning first
      ExRatatui.textarea_handle_key(state, "home", [])
      assert {0, 0} = ExRatatui.textarea_cursor(state)

      # Ctrl+E (Emacs: end of line)
      ExRatatui.textarea_handle_key(state, "e", ["ctrl"])
      {_row, col} = ExRatatui.textarea_cursor(state)
      assert col == 5
    end

    test "insert_str pastes multi-line content as real new lines" do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_insert_str(state, "line1\nline2\nline3")
      assert ExRatatui.textarea_get_value(state) == "line1\nline2\nline3"
      assert ExRatatui.textarea_line_count(state) == 3
      assert ExRatatui.textarea_cursor(state) == {2, 5}
    end

    test "insert_str normalizes CRLF to LF" do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_insert_str(state, "a\r\nb")
      assert ExRatatui.textarea_get_value(state) == "a\nb"
      assert ExRatatui.textarea_line_count(state) == 2
    end

    test "insert_str inserts at current cursor position" do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_set_value(state, "hello world")
      ExRatatui.textarea_handle_key(state, "home", [])
      for _ <- 1..5, do: ExRatatui.textarea_handle_key(state, "right", [])
      ExRatatui.textarea_insert_str(state, " cruel")
      assert ExRatatui.textarea_get_value(state) == "hello cruel world"
    end
  end
end
