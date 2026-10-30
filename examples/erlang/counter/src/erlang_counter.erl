%% The counter from examples/basics/reducer_counter_app.exs, written in Erlang.
-module(erlang_counter).

-behaviour('Elixir.ExRatatui.App').

-export([start/0, headless/0]).
-export([mount/1, render/2, handle_event/2, handle_info/2, subscriptions/1]).

%% Runs the TUI in this terminal until q.
start() ->
    {ok, Pid} = 'Elixir.ExRatatui.App':start_link(?MODULE, [{name, nil}]),
    Ref = monitor(process, Pid),
    receive
        {'DOWN', Ref, process, Pid, _Reason} -> ok
    end.

%% Draws one frame on a test terminal and returns its text, with no terminal needed.
headless() ->
    Terminal = 'Elixir.ExRatatui':init_test_terminal(60, 12),
    {ok, Model} = mount([]),
    Frame = 'Elixir.ExRatatui.Frame':'__struct__'(#{width => 60, height => 12}),
    ok = 'Elixir.ExRatatui':draw(Terminal, render(Model, Frame)),
    'Elixir.ExRatatui':get_buffer_content(Terminal).

mount(_Opts) ->
    {ok, #{count => 0, ticks => 0}}.

update(up, #{count := Count} = Model) ->
    {noreply, Model#{count := Count + 1}};
update(down, #{count := Count} = Model) ->
    {noreply, Model#{count := Count - 1}};
%% Nothing on screen has to change right now, so the tick shows up on the next key's frame.
update(tick, #{ticks := Ticks} = Model) ->
    {noreply, Model#{ticks := Ticks + 1}, [{'render?', false}]};
update(quit, Model) ->
    {stop, Model}.

handle_event(#{'__struct__' := 'Elixir.ExRatatui.Event.Key', code := Code, kind := <<"press">>}, Model) ->
    case Code of
        <<"up">> -> update(up, Model);
        <<"k">> -> update(up, Model);
        <<"down">> -> update(down, Model);
        <<"j">> -> update(down, Model);
        <<"q">> -> update(quit, Model);
        _ -> {noreply, Model}
    end;
handle_event(_Event, Model) ->
    {noreply, Model}.

handle_info(tick, Model) ->
    update(tick, Model);
handle_info(_Message, Model) ->
    {noreply, Model}.

subscriptions(_Model) ->
    ['Elixir.ExRatatui.Subscription':interval(counter_tick, 1000, tick)].

render(#{count := Count, ticks := Ticks}, #{width := Width, height := Height}) ->
    Area = 'Elixir.ExRatatui.Layout.Rect':'__struct__'(#{x => 0, y => 0, width => Width, height => Height}),
    [HeaderArea, BodyArea, FooterArea] =
        'Elixir.ExRatatui.Layout':split(Area, vertical, [{length, 3}, {min, 0}, {length, 3}]),

    Header = paragraph(
        <<"  ExRatatui Counter (Erlang)">>,
        left,
        style(cyan, [bold]),
        block([all], rounded, style(dark_gray, []))
    ),
    Body = paragraph(
        iolist_to_binary([<<"\n\nCounter: ">>, integer_to_binary(Count), <<"\nTicks: ">>, integer_to_binary(Ticks)]),
        center,
        style(white, [bold]),
        block([all], rounded, style(cyan, []))
    ),
    Footer = paragraph(
        <<" Up/k = +1  |  Down/j = -1  |  q = quit">>,
        left,
        style(dark_gray, []),
        block([top], plain, style(dark_gray, []))
    ),

    [{Header, HeaderArea}, {Body, BodyArea}, {Footer, FooterArea}].

paragraph(Text, Alignment, Style, Block) ->
    'Elixir.ExRatatui.Widgets.Paragraph':'__struct__'(#{
        text => Text,
        alignment => Alignment,
        style => Style,
        block => Block
    }).

block(Borders, BorderType, BorderStyle) ->
    'Elixir.ExRatatui.Widgets.Block':'__struct__'(#{
        borders => Borders,
        border_type => BorderType,
        border_style => BorderStyle
    }).

style(Color, Modifiers) ->
    'Elixir.ExRatatui.Style':'__struct__'(#{fg => Color, modifiers => Modifiers}).
