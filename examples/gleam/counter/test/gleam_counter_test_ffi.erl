%% Drives the app headlessly, the way test_mode expects.
-module(gleam_counter_test_ffi).

-export([
    press/2,
    send_message/2,
    send_unknown/1,
    model/1,
    buffer/1,
    render_count/1,
    subscription_count/1,
    stop/1,
    exited_normally/1
]).

press(Pid, Code) ->
    Key = 'Elixir.ExRatatui.Event.Key':'__struct__'(#{code => Code, kind => <<"press">>}),
    ok = 'Elixir.ExRatatui.Runtime':inject_event(Pid, Key),
    nil.

send_message(Pid, Message) ->
    Pid ! Message,
    nil.

send_unknown(Pid) ->
    send_message(Pid, {something, "else"}).

model(Pid) ->
    maps:get(user_state, sys:get_state(Pid)).

buffer(Pid) ->
    #{terminal_ref := Terminal} = sys:get_state(Pid),
    'Elixir.ExRatatui':get_buffer_content(Terminal).

render_count(Pid) ->
    maps:get(render_count, 'Elixir.ExRatatui.Runtime':snapshot(Pid)).

subscription_count(Pid) ->
    maps:get(subscription_count, 'Elixir.ExRatatui.Runtime':snapshot(Pid)).

stop(Pid) ->
    ok = gen_server:stop(Pid),
    nil.

exited_normally(Pid) ->
    Ref = monitor(process, Pid),
    receive
        {'DOWN', Ref, process, Pid, Reason} -> Reason =:= normal orelse Reason =:= noproc
    after 2000 -> false
    end.
