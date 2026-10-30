//// The counter from `examples/basics/reducer_counter_app.exs`, written in Gleam.
////
//// ExRatatui calls `mount`, `render`, `handle_event`, `handle_info`, and `subscriptions` by name. Custom types compile to the atoms and tuples it expects: `Noreply(model)` is `{noreply, Model}`, `Length(3)` is `{length, 3}`, and `DarkGray` is `dark_gray`. What Gleam can't write lives in `gleam_counter_ffi.erl`.

import gleam/dynamic.{type Dynamic}
import gleam/int

// The app

pub type Model {
  Model(count: Int, ticks: Int)
}

pub type Msg {
  Up
  Down
  Tick
  Quit
}

pub type Next {
  Noreply(Model)
  Stop(Model)
}

pub fn mount(_options: Dynamic) -> Result(Model, Nil) {
  Ok(Model(count: 0, ticks: 0))
}

fn update(msg: Msg, model: Model) -> Next {
  case msg {
    Up -> Noreply(Model(..model, count: model.count + 1))
    Down -> Noreply(Model(..model, count: model.count - 1))
    // Nothing on screen has to change right now, so the tick shows up on the next key's frame.
    Tick -> skip_render(Model(..model, ticks: model.ticks + 1))
    Quit -> Stop(model)
  }
}

pub fn handle_event(event: Event, model: Model) -> Next {
  case key_press(event) {
    Ok("up") | Ok("k") -> update(Up, model)
    Ok("down") | Ok("j") -> update(Down, model)
    Ok("q") -> update(Quit, model)
    _ -> Noreply(model)
  }
}

// The runtime passes whatever reaches its mailbox, so the catch-all stays even though `Msg` says only `Tick` should.
pub fn handle_info(message: Msg, model: Model) -> Next {
  case message {
    Tick -> update(Tick, model)
    _ -> Noreply(model)
  }
}

pub fn subscriptions(_model: Model) -> List(Subscription) {
  [interval(CounterTick, 1000, Tick)]
}

pub fn render(model: Model, frame: Frame) -> List(#(Widget, Rect)) {
  let assert [header_area, body_area, footer_area] =
    split(area(frame), Vertical, [Length(3), Min(0), Length(3)])

  let header =
    paragraph(
      "  ExRatatui Counter (Gleam)",
      Left,
      style(Cyan, [Bold]),
      block([All], Rounded, style(DarkGray, [])),
    )

  let body =
    paragraph(
      "\n\nCounter: "
        <> int.to_string(model.count)
        <> "\nTicks: "
        <> int.to_string(model.ticks),
      Center,
      style(White, [Bold]),
      block([All], Rounded, style(Cyan, [])),
    )

  let footer =
    paragraph(
      " Up/k = +1  |  Down/j = -1  |  q = quit",
      Left,
      style(DarkGray, []),
      block([Top], Plain, style(DarkGray, [])),
    )

  [#(header, header_area), #(body, body_area), #(footer, footer_area)]
}

pub fn main() -> Nil {
  let assert Ok(pid) = start([Name(Nil)])
  wait_for_exit(pid)
}

pub fn start(options: List(StartOption)) -> Result(Pid, Dynamic) {
  start_link(GleamCounter, options)
}

// The ExRatatui API

pub type AppModule {
  GleamCounter
}

pub type StartOption {
  Name(Nil)
  TestMode(#(Int, Int))
}

pub type SubscriptionId {
  CounterTick
}

pub type Direction {
  Vertical
}

pub type Constraint {
  Length(Int)
  Min(Int)
}

pub type Color {
  Cyan
  White
  DarkGray
}

pub type Modifier {
  Bold
}

pub type Border {
  All
  Top
}

pub type BorderType {
  Plain
  Rounded
}

pub type Alignment {
  Left
  Center
}

pub type Pid

pub type Event

pub type Frame

pub type Rect

pub type Widget

pub type Style

pub type Block

pub type Subscription

@external(erlang, "Elixir.ExRatatui.App", "start_link")
fn start_link(
  module: AppModule,
  options: List(StartOption),
) -> Result(Pid, Dynamic)

@external(erlang, "Elixir.ExRatatui.Subscription", "interval")
fn interval(id: SubscriptionId, milliseconds: Int, message: Msg) -> Subscription

@external(erlang, "Elixir.ExRatatui.Layout", "split")
fn split(
  area: Rect,
  direction: Direction,
  constraints: List(Constraint),
) -> List(Rect)

@external(erlang, "gleam_counter_ffi", "area")
fn area(frame: Frame) -> Rect

@external(erlang, "gleam_counter_ffi", "style")
fn style(color: Color, modifiers: List(Modifier)) -> Style

@external(erlang, "gleam_counter_ffi", "block")
fn block(
  borders: List(Border),
  border_type: BorderType,
  border_style: Style,
) -> Block

@external(erlang, "gleam_counter_ffi", "paragraph")
fn paragraph(
  text: String,
  alignment: Alignment,
  style: Style,
  block: Block,
) -> Widget

@external(erlang, "gleam_counter_ffi", "key_press")
fn key_press(event: Event) -> Result(String, Nil)

@external(erlang, "gleam_counter_ffi", "skip_render")
fn skip_render(model: Model) -> Next

@external(erlang, "gleam_counter_ffi", "wait_for_exit")
fn wait_for_exit(pid: Pid) -> Nil
