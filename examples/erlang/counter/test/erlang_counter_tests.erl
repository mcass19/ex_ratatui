%% Drives the app on a headless terminal, using test_mode and ExRatatui.Runtime.inject_event/2.
-module(erlang_counter_tests).

-include_lib("eunit/include/eunit.hrl").

keys_change_the_count_test() ->
    Pid = start(),

    [press(Pid, Code) || Code <- [<<"up">>, <<"k">>, <<"up">>, <<"down">>, <<"x">>]],

    ?assertEqual(#{count => 2, ticks => 0}, model(Pid)),
    ?assert(contains(buffer(Pid), <<"Counter: 2">>)),

    stop(Pid).

tick_updates_the_model_without_a_frame_test() ->
    Pid = start(),
    Frames = snapshot(Pid, render_count),

    Pid ! tick,

    ?assertEqual(#{count => 0, ticks => 1}, model(Pid)),
    ?assertEqual(Frames, snapshot(Pid, render_count)),
    ?assert(contains(buffer(Pid), <<"Ticks: 0">>)),

    press(Pid, <<"up">>),
    ?assert(contains(buffer(Pid), <<"Ticks: 1">>)),

    stop(Pid).

other_messages_and_events_are_ignored_test() ->
    Pid = start(),

    Pid ! {something, unexpected},
    Resize = 'Elixir.ExRatatui.Event.Resize':'__struct__'(#{width => 60, height => 12}),
    ok = 'Elixir.ExRatatui.Runtime':inject_event(Pid, Resize),

    ?assertEqual(#{count => 0, ticks => 0}, model(Pid)),

    stop(Pid).

the_subscription_is_active_test() ->
    Pid = start(),

    ?assertEqual(1, snapshot(Pid, subscription_count)),

    stop(Pid).

q_quits_test() ->
    Pid = start(),
    Ref = monitor(process, Pid),

    press(Pid, <<"q">>),

    receive
        {'DOWN', Ref, process, Pid, Reason} -> ?assertEqual(normal, Reason)
    after 2000 -> error(timeout)
    end.

headless_draws_a_frame_test() ->
    ?assert(contains(erlang_counter:headless(), <<"Counter: 0">>)).

start() ->
    Opts = [{name, nil}, {test_mode, {60, 12}}],
    {ok, Pid} = 'Elixir.ExRatatui.App':start_link(erlang_counter, Opts),
    Pid.

stop(Pid) ->
    ok = gen_server:stop(Pid).

press(Pid, Code) ->
    Key = 'Elixir.ExRatatui.Event.Key':'__struct__'(#{code => Code, kind => <<"press">>}),
    ok = 'Elixir.ExRatatui.Runtime':inject_event(Pid, Key).

model(Pid) ->
    maps:get(user_state, sys:get_state(Pid)).

buffer(Pid) ->
    #{terminal_ref := Terminal} = sys:get_state(Pid),
    'Elixir.ExRatatui':get_buffer_content(Terminal).

snapshot(Pid, Key) ->
    maps:get(Key, 'Elixir.ExRatatui.Runtime':snapshot(Pid)).

contains(Text, Part) ->
    string:find(Text, Part) =/= nomatch.
