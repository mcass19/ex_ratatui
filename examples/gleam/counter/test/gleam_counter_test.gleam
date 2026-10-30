import gleam/string
import gleam_counter.{type Model, type Pid, Model, Name, TestMode, Tick}
import gleeunit

pub fn main() -> Nil {
  gleeunit.main()
}

fn start() -> Pid {
  let assert Ok(pid) = gleam_counter.start([Name(Nil), TestMode(#(60, 12))])
  pid
}

pub fn keys_change_the_count_test() {
  let pid = start()

  press(pid, "up")
  press(pid, "k")
  press(pid, "up")
  press(pid, "down")
  press(pid, "x")

  assert model(pid) == Model(count: 2, ticks: 0)
  assert string.contains(buffer(pid), "Counter: 2")

  stop(pid)
}

pub fn tick_updates_the_model_without_a_frame_test() {
  let pid = start()
  let frames = render_count(pid)

  send(pid, Tick)

  assert model(pid) == Model(count: 0, ticks: 1)
  assert render_count(pid) == frames
  assert string.contains(buffer(pid), "Ticks: 0")

  press(pid, "up")
  assert string.contains(buffer(pid), "Ticks: 1")

  stop(pid)
}

pub fn unknown_messages_are_ignored_test() {
  let pid = start()

  send_unknown(pid)

  assert model(pid) == Model(count: 0, ticks: 0)

  stop(pid)
}

pub fn the_subscription_is_active_test() {
  let pid = start()

  assert subscription_count(pid) == 1

  stop(pid)
}

pub fn q_quits_test() {
  let pid = start()

  press(pid, "q")

  assert exited_normally(pid)
}

@external(erlang, "gleam_counter_test_ffi", "press")
fn press(pid: Pid, code: String) -> Nil

@external(erlang, "gleam_counter_test_ffi", "send_message")
fn send(pid: Pid, message: gleam_counter.Msg) -> Nil

@external(erlang, "gleam_counter_test_ffi", "send_unknown")
fn send_unknown(pid: Pid) -> Nil

@external(erlang, "gleam_counter_test_ffi", "model")
fn model(pid: Pid) -> Model

@external(erlang, "gleam_counter_test_ffi", "buffer")
fn buffer(pid: Pid) -> String

@external(erlang, "gleam_counter_test_ffi", "render_count")
fn render_count(pid: Pid) -> Int

@external(erlang, "gleam_counter_test_ffi", "subscription_count")
fn subscription_count(pid: Pid) -> Int

@external(erlang, "gleam_counter_test_ffi", "stop")
fn stop(pid: Pid) -> Nil

@external(erlang, "gleam_counter_test_ffi", "exited_normally")
fn exited_normally(pid: Pid) -> Bool
