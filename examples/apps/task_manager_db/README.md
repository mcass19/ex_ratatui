# Task Manager — ExRatatui + Ecto Demo

A terminal task manager built with [ExRatatui](https://github.com/mcass19/ex_ratatui) and [Ecto](https://github.com/elixir-ecto/ecto) + SQLite. Demonstrates how to build a supervised, database-backed TUI application using the `ExRatatui.App` behaviour.

## What This Shows

- Using the `ExRatatui.App` behaviour with `mount/1`, `render/2`, and `handle_event/2` callbacks
- OTP supervision with the Repo and TUI running side-by-side under a single supervisor
- Ecto and SQLite for persistent task storage
- Full CRUD operations driven from the terminal
- Layout composition with Table, Gauge, and Paragraph widgets

## Setup

```bash
cd examples/task_manager
mix deps.get
mix ecto.setup
```

## Run

### Local mode (default)

```bash
mix run --no-halt
```

`--no-halt` keeps the BEAM VM alive after starting the application. Without it, the VM would exit immediately after booting the supervision tree, killing the TUI process.

Data is stored in a local SQLite file at `task_manager_dev.db` (or `task_manager_test.db` for tests).

### SSH mode — serve the TUI to multiple clients

Set `TASK_MANAGER_SSH=1` before starting the app and the supervision tree will swap `TaskManager.TUI` for an `ExRatatui.SSH.Daemon` child, listening on port 2222 with password auth:

```bash
TASK_MANAGER_SSH=1 mix run --no-halt
```

In another terminal (or from another machine):

```bash
ssh demo@localhost -p 2222
# password: demo
```

Every SSH client gets its own isolated `ExRatatui.App` session, but they **all share the same SQLite database** — add a task in one session and the others will see it on their next render. That's the interesting bit about this example: it's a multi-user, database-backed TUI served over SSH from a single BEAM node.

The daemon generates a throwaway host key under your system tmp dir on first start. You can tune the port, user, and password with extra env vars:

| Env var | Default | Description |
|---------|---------|-------------|
| `TASK_MANAGER_SSH` | `0` | Any truthy value switches to SSH mode |
| `TASK_MANAGER_SSH_PORT` | `2222` | TCP port the daemon listens on |
| `TASK_MANAGER_SSH_USER` | `demo` | SSH username |
| `TASK_MANAGER_SSH_PASSWORD` | `demo` | SSH password |

```bash
TASK_MANAGER_SSH=1 TASK_MANAGER_SSH_PORT=3333 \
  TASK_MANAGER_SSH_USER=alice TASK_MANAGER_SSH_PASSWORD=s3cret \
  mix run --no-halt
```

Pressing `q` inside an SSH session disconnects that one client but leaves the daemon and other clients running. Stop the daemon with `Ctrl-C` twice.

## Controls

| Key | Action |
|-----|--------|
| `j` / `Down` | Move selection down |
| `k` / `Up` | Move selection up |
| `Enter` | Toggle task status (Todo -> In Progress -> Done) |
| `p` | Cycle priority (High -> Med -> Low) |
| `n` | Create new task (type name, Enter to confirm) |
| `d` | Delete selected task |
| `f` | Cycle filter (All / Todo / In Progress / Done) |
| `Esc` | Cancel input |
| `q` | Quit |
