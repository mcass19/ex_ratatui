%% What Gleam can't write: Elixir structs, and the atom 'render?'.
-module(gleam_counter_ffi).

-export([area/1, style/2, block/3, paragraph/4, key_press/1, skip_render/1, wait_for_exit/1]).

area(#{width := Width, height := Height}) ->
    'Elixir.ExRatatui.Layout.Rect':'__struct__'(#{x => 0, y => 0, width => Width, height => Height}).

style(Color, Modifiers) ->
    'Elixir.ExRatatui.Style':'__struct__'(#{fg => Color, modifiers => Modifiers}).

block(Borders, BorderType, BorderStyle) ->
    'Elixir.ExRatatui.Widgets.Block':'__struct__'(#{
        borders => Borders,
        border_type => BorderType,
        border_style => BorderStyle
    }).

paragraph(Text, Alignment, Style, Block) ->
    'Elixir.ExRatatui.Widgets.Paragraph':'__struct__'(#{
        text => Text,
        alignment => Alignment,
        style => Style,
        block => Block
    }).

key_press(#{'__struct__' := 'Elixir.ExRatatui.Event.Key', code := Code, kind := <<"press">>}) ->
    {ok, Code};
key_press(_Event) ->
    {error, nil}.

skip_render(Model) ->
    {noreply, Model, [{'render?', false}]}.

%% `gleam run` halts the VM as soon as main returns.
wait_for_exit(Pid) ->
    Ref = monitor(process, Pid),
    receive
        {'DOWN', Ref, process, Pid, _Reason} -> nil
    end.
