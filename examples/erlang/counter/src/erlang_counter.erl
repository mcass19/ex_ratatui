%% The counter from examples/basics/reducer_counter_app.exs, written in Erlang, plus a text input that logs labelled counts to a table.
-module(erlang_counter).

-behaviour('Elixir.ExRatatui.App').

-export([start/0]).
-export([mount/1, render/2, handle_event/2, handle_info/2, subscriptions/1]).

%% Runs the TUI in this terminal until Esc.
start() ->
    {ok, Pid} = 'Elixir.ExRatatui.App':start_link(?MODULE, [{name, nil}]),
    Ref = monitor(process, Pid),
    receive
        {'DOWN', Ref, process, Pid, _Reason} -> ok
    end.

mount(_Opts) ->
    %% The text input keeps its state in the NIF, so the model holds a reference that typing updates in place.
    {ok, #{count => 0, ticks => 0, input => 'Elixir.ExRatatui':text_input_new(), log => []}}.

update(up, #{count := Count} = Model) ->
    {noreply, Model#{count := Count + 1}};
update(down, #{count := Count} = Model) ->
    {noreply, Model#{count := Count - 1}};
update({type, Code}, #{input := Input} = Model) ->
    ok = 'Elixir.ExRatatui':text_input_handle_key(Input, Code),
    {noreply, Model};
update(log, #{count := Count, input := Input, log := Log} = Model) ->
    Label = 'Elixir.ExRatatui':text_input_get_value(Input),
    ok = 'Elixir.ExRatatui':text_input_set_value(Input, <<>>),
    {noreply, Model#{log := [{Label, Count} | Log]}};
%% Nothing on screen has to change right now, so the tick shows up on the next key's frame.
update(tick, #{ticks := Ticks} = Model) ->
    {noreply, Model#{ticks := Ticks + 1}, [{'render?', false}]};
update(quit, Model) ->
    {stop, Model}.

handle_event(#{'__struct__' := 'Elixir.ExRatatui.Event.Key', code := Code, kind := <<"press">>}, Model) ->
    case Code of
        <<"up">> -> update(up, Model);
        <<"down">> -> update(down, Model);
        <<"enter">> -> update(log, Model);
        <<"esc">> -> update(quit, Model);
        _ -> update({type, Code}, Model)
    end;
handle_event(_Event, Model) ->
    {noreply, Model}.

handle_info(tick, Model) ->
    update(tick, Model);
handle_info(_Message, Model) ->
    {noreply, Model}.

subscriptions(_Model) ->
    ['Elixir.ExRatatui.Subscription':interval(counter_tick, 1000, tick)].

render(#{count := Count, ticks := Ticks, input := Input, log := Log}, #{width := Width, height := Height}) ->
    Area = 'Elixir.ExRatatui.Layout.Rect':'__struct__'(#{x => 0, y => 0, width => Width, height => Height}),
    [HeaderArea, CounterArea, InputArea, LogArea, FooterArea] =
        'Elixir.ExRatatui.Layout':split(Area, vertical, [{length, 3}, {length, 4}, {length, 3}, {min, 0}, {length, 3}]),

    Header = paragraph(
        <<"  ExRatatui Counter (Erlang)">>,
        left,
        style(cyan, [bold]),
        block([all], rounded, style(dark_gray, []))
    ),
    Counter = paragraph(
        iolist_to_binary([<<"Counter: ">>, integer_to_binary(Count), <<"\nTicks: ">>, integer_to_binary(Ticks)]),
        center,
        style(white, [bold]),
        block([all], rounded, style(cyan, []))
    ),
    TextInput = 'Elixir.ExRatatui.Widgets.TextInput':'__struct__'(#{
        state => Input,
        placeholder => <<"Type a label, Enter logs it">>,
        placeholder_style => style(dark_gray, []),
        block => block([all], rounded, style(cyan, []))
    }),
    Table = 'Elixir.ExRatatui.Widgets.Table':'__struct__'(#{
        header => [<<"Label">>, <<"Count">>],
        header_style => style(cyan, [bold]),
        rows => [[Label, integer_to_binary(Value)] || {Label, Value} <- Log],
        widths => [{min, 0}, {length, 6}],
        block => block([all], rounded, style(dark_gray, []))
    }),
    Footer = paragraph(
        <<" Up/Down = count  |  Enter = log  |  Esc = quit">>,
        left,
        style(dark_gray, []),
        block([top], plain, style(dark_gray, []))
    ),

    [
        {Header, HeaderArea},
        {Counter, CounterArea},
        {TextInput, InputArea},
        {Table, LogArea},
        {Footer, FooterArea}
    ].

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
