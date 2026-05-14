defmodule ExRatatui.CodeBlockTest do
  use ExUnit.Case, async: true

  alias ExRatatui.CodeBlock
  alias ExRatatui.Style
  alias ExRatatui.Text.{Line, Span}

  doctest ExRatatui.CodeBlock

  describe "resolve_theme/1" do
    test "passes raw strings through unchanged" do
      assert CodeBlock.resolve_theme("InspiredGitHub") == "InspiredGitHub"
      assert CodeBlock.resolve_theme("My-Custom-Theme") == "My-Custom-Theme"
    end

    test "maps each curated atom to its syntect name" do
      mappings = [
        {:base16_ocean_dark, "base16-ocean.dark"},
        {:base16_ocean_light, "base16-ocean.light"},
        {:base16_eighties_dark, "base16-eighties.dark"},
        {:base16_mocha_dark, "base16-mocha.dark"},
        {:inspired_github, "InspiredGitHub"},
        {:solarized_dark, "Solarized (dark)"},
        {:solarized_light, "Solarized (light)"}
      ]

      for {atom, name} <- mappings do
        assert CodeBlock.resolve_theme(atom) == name
      end
    end

    test "raises with valid atoms listed on unknown atom" do
      err =
        assert_raise ArgumentError, fn ->
          CodeBlock.resolve_theme(:no_such_theme)
        end

      msg = Exception.message(err)
      assert msg =~ "unknown CodeBlock theme :no_such_theme"
      assert msg =~ ":base16_ocean_dark"
      assert msg =~ ":solarized_light"
    end
  end

  describe "highlight/3" do
    test "returns a list of Line structs with at least one Span each" do
      [first | _] = CodeBlock.highlight("fn main() {}", "rust", :base16_ocean_dark)
      assert %Line{} = first
      assert [%Span{} | _] = first.spans
    end

    test "nil language yields a single span per line carrying the input verbatim" do
      [%Line{spans: spans}] = CodeBlock.highlight("hello", nil, :base16_ocean_dark)
      assert length(spans) == 1
      assert hd(spans).content =~ "hello"
    end

    test "unknown language falls back to plain text" do
      [%Line{spans: spans}] =
        CodeBlock.highlight("anything", "not-a-language", :base16_ocean_dark)

      assert Enum.map_join(spans, & &1.content) =~ "anything"
    end

    test "rust source produces multiple spans with distinct fg colors" do
      fgs =
        "fn main() { let x: i32 = 42; }"
        |> CodeBlock.highlight("rust", :base16_ocean_dark)
        |> Enum.flat_map(fn %Line{spans: spans} -> Enum.map(spans, & &1.style.fg) end)
        |> Enum.uniq()

      assert length(fgs) >= 2
    end

    test "fg colors are {:rgb, r, g, b} tuples" do
      [%Line{spans: spans} | _] =
        CodeBlock.highlight("fn main() {}", "rust", :base16_ocean_dark)

      assert Enum.any?(spans, fn %Span{style: %Style{fg: fg}} ->
               match?({:rgb, _, _, _}, fg)
             end)
    end

    test "accepts a raw theme string" do
      [%Line{} | _] = CodeBlock.highlight("x", "rust", "InspiredGitHub")
    end

    test "raises on unknown theme atom (before crossing the NIF)" do
      assert_raise ArgumentError, ~r/unknown CodeBlock theme/, fn ->
        CodeBlock.highlight("x", "rust", :no_such_theme)
      end
    end

    test "empty input yields zero or more lines without crashing" do
      result = CodeBlock.highlight("", "rust", :base16_ocean_dark)
      assert is_list(result)
    end

    test "multi-line input produces one Line per source line" do
      lines = CodeBlock.highlight("a\nb\nc", nil, :base16_ocean_dark)
      assert length(lines) == 3
    end
  end

  describe "from_native/1 (NIF response → structs)" do
    test "nil fg/bg pass through as nil" do
      raw = [
        [
          %{
            content: "x",
            fg: nil,
            bg: nil,
            bold: false,
            italic: false,
            underlined: false
          }
        ]
      ]

      assert [%Line{spans: [%Span{style: %Style{fg: nil, bg: nil, modifiers: []}}]}] =
               CodeBlock.from_native(raw)
    end

    test "rgb tuples become {:rgb, r, g, b}" do
      raw = [
        [
          %{
            content: "x",
            fg: {10, 20, 30},
            bg: {40, 50, 60},
            bold: false,
            italic: false,
            underlined: false
          }
        ]
      ]

      assert [
               %Line{
                 spans: [%Span{style: %Style{fg: {:rgb, 10, 20, 30}, bg: {:rgb, 40, 50, 60}}}]
               }
             ] =
               CodeBlock.from_native(raw)
    end

    test "modifier flags collect into the modifiers list" do
      raw = [
        [
          %{
            content: "x",
            fg: nil,
            bg: nil,
            bold: true,
            italic: true,
            underlined: true
          }
        ]
      ]

      assert [%Line{spans: [%Span{style: %Style{modifiers: mods}}]}] = CodeBlock.from_native(raw)
      assert Enum.sort(mods) == [:bold, :italic, :underlined]
    end

    test "partial modifier flags only collect the active ones" do
      raw = [
        [
          %{
            content: "x",
            fg: nil,
            bg: nil,
            bold: false,
            italic: true,
            underlined: false
          }
        ]
      ]

      assert [%Line{spans: [%Span{style: %Style{modifiers: [:italic]}}]}] =
               CodeBlock.from_native(raw)
    end
  end

  describe "telemetry [:ex_ratatui, :code_block, :highlight]" do
    setup do
      ref = make_ref()

      :telemetry.attach_many(
        ref,
        [
          [:ex_ratatui, :code_block, :highlight, :start],
          [:ex_ratatui, :code_block, :highlight, :stop]
        ],
        &__MODULE__.forward_tel/4,
        %{probe: self()}
      )

      on_exit(fn -> :telemetry.detach(ref) end)
      :ok
    end

    test "emits start + stop with language, theme, bytes, and line_count" do
      _ = CodeBlock.highlight("fn main() {}\nfn other() {}", "rust", :solarized_dark)

      assert_receive {:tel, [:ex_ratatui, :code_block, :highlight, :start], start_meas,
                      %{language: "rust", theme: "Solarized (dark)", bytes: bytes}}

      assert is_integer(start_meas.monotonic_time)
      assert bytes == byte_size("fn main() {}\nfn other() {}")

      assert_receive {:tel, [:ex_ratatui, :code_block, :highlight, :stop], stop_meas,
                      %{
                        language: "rust",
                        theme: "Solarized (dark)",
                        bytes: ^bytes,
                        line_count: line_count
                      }}

      assert is_integer(stop_meas.duration)
      assert line_count >= 1
    end

    test "passes nil language through to telemetry metadata" do
      _ = CodeBlock.highlight("hello", nil, :base16_ocean_dark)

      assert_receive {:tel, [:ex_ratatui, :code_block, :highlight, :start], _, %{language: nil}}

      assert_receive {:tel, [:ex_ratatui, :code_block, :highlight, :stop], _,
                      %{language: nil, line_count: 1}}
    end
  end

  # Captured module function — :telemetry warns at info level when
  # attached handlers are local/anonymous functions, citing a perf
  # penalty per dispatch. Using `&__MODULE__.forward_tel/4` silences it.
  def forward_tel(event, measurements, metadata, %{probe: probe}) do
    send(probe, {:tel, event, measurements, metadata})
  end
end
