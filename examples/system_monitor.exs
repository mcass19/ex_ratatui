# Example: system monitor using ExRatatui.App.
#
# ┌─────────────────────────────────────────────────────────────────┐
# │                              MODES                              │
# └─────────────────────────────────────────────────────────────────┘
#
#  1) Local terminal (what you usually want):
#
#         mix run examples/system_monitor.exs
#
#  2) Over SSH — generates a throwaway host key and listens on 2222
#     with user/password "demo/demo". Connect from another terminal
#     (or another machine) with `ssh demo@localhost -p 2222`. `q`
#     inside the TUI disconnects *that* client but the daemon keeps
#     running, so multiple clients can attach concurrently.
#
#         mix run --no-halt examples/system_monitor.exs --ssh
#         mix run --no-halt examples/system_monitor.exs --ssh 2223
#
#  3) Over Erlang distribution — starts a Listener that waits for
#     remote nodes to attach. From another node, call
#     `ExRatatui.Distributed.attach(:"app@host", SystemMonitor)`.
#
#         elixir --sname app --cookie demo -S mix run --no-halt \
#           examples/system_monitor.exs --distributed
#
# Controls: q = quit, r = refresh (auto-refreshes every 2 seconds).
#
# This example demonstrates a system monitor dashboard that reads
# CPU temperature, memory usage, network info, and BEAM stats.
# Designed to work when SSH'd into a Nerves device (or any Linux box).

alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, Gauge, Paragraph, Table}
alias ExRatatui.Event

defmodule SystemMonitor do
  use ExRatatui.App

  @refresh_interval 2_000

  @impl true
  def mount(_opts) do
    schedule_refresh()
    {:ok, collect_stats()}
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state) do
    {:stop, state}
  end

  def handle_event(%Event.Key{code: "r", kind: "press"}, state) do
    {:noreply, collect_stats(state)}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:refresh, state) do
    schedule_refresh()
    {:noreply, collect_stats(state)}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [header_area, body_area, footer_area] =
      Layout.split(area, :vertical, [{:length, 3}, {:min, 0}, {:length, 3}])

    # Body: two columns
    [left_col, right_col] =
      Layout.split(body_area, :horizontal, [{:percentage, 50}, {:percentage, 50}])

    # Left column: CPU temp gauge + Memory gauge
    [cpu_area, mem_area, disk_area] =
      Layout.split(left_col, :vertical, [{:length, 3}, {:length, 3}, {:length, 3}])

    # Right column: network table + BEAM stats
    [net_area, beam_area] =
      Layout.split(right_col, :vertical, [{:length, 7}, {:min, 0}])

    header = header_widget(state)
    cpu_gauge = cpu_temp_widget(state)
    mem_gauge = memory_widget(state)
    disk_gauge = disk_widget(state)
    net_table = network_widget(state)
    beam_info = beam_widget(state)
    footer = footer_widget()

    [
      {header, header_area},
      {cpu_gauge, cpu_area},
      {mem_gauge, mem_area},
      {disk_gauge, disk_area},
      {net_table, net_area},
      {beam_info, beam_area},
      {footer, footer_area}
    ]
  end

  # -- Widget builders --

  defp header_widget(state) do
    hostname = state.hostname
    uptime = format_uptime(state.uptime_seconds)

    %Paragraph{
      text: "  #{hostname}    Uptime: #{uptime}",
      style: %Style{fg: :cyan, modifiers: [:bold]},
      block: %Block{
        title: " System Monitor ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }
  end

  defp cpu_temp_widget(state) do
    {ratio, label, color} =
      case state.cpu_temp do
        nil ->
          {0.0, "N/A", :dark_gray}

        temp ->
          r = min(temp / 85.0, 1.0)

          color =
            cond do
              temp >= 70 -> :red
              temp >= 55 -> :yellow
              true -> :green
            end

          {r, "#{Float.round(temp, 1)}C", color}
      end

    %Gauge{
      ratio: ratio,
      label: label,
      gauge_style: %Style{fg: color},
      block: %Block{
        title: " CPU Temp ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }
  end

  defp memory_widget(state) do
    {ratio, label} =
      case state.memory do
        %{total: total, used: used} when total > 0 ->
          r = used / total
          {r, "#{format_mb(used)} / #{format_mb(total)} MB"}

        _ ->
          {0.0, "N/A"}
      end

    color =
      cond do
        ratio >= 0.9 -> :red
        ratio >= 0.7 -> :yellow
        true -> :green
      end

    %Gauge{
      ratio: ratio,
      label: label,
      gauge_style: %Style{fg: color},
      block: %Block{
        title: " Memory ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }
  end

  defp disk_widget(state) do
    {ratio, label} =
      case state.disk do
        %{total: total, used: used} when total > 0 ->
          r = used / total
          {r, "#{format_gb(used)} / #{format_gb(total)} GB"}

        _ ->
          {0.0, "N/A"}
      end

    color =
      cond do
        ratio >= 0.9 -> :red
        ratio >= 0.7 -> :yellow
        true -> :green
      end

    %Gauge{
      ratio: ratio,
      label: label,
      gauge_style: %Style{fg: color},
      block: %Block{
        title: " Disk (/) ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }
  end

  defp network_widget(state) do
    rows =
      Enum.map(state.interfaces, fn {name, ip} ->
        [name, ip]
      end)

    rows = if rows == [], do: [["--", "no interfaces"]], else: rows

    %Table{
      header: ["Interface", "IP Address"],
      rows: rows,
      widths: [{:percentage, 40}, {:percentage, 60}],
      style: %Style{fg: :white},
      block: %Block{
        title: " Network ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }
  end

  defp beam_widget(state) do
    beam = state.beam

    lines = [
      "  Processes:  #{beam.processes}",
      "  Ports:      #{beam.ports}",
      "  Total mem:  #{format_mb(beam.total_memory)} MB",
      "  Proc mem:   #{format_mb(beam.process_memory)} MB",
      "  ETS mem:    #{format_mb(beam.ets_memory)} MB",
      "  Atoms:      #{beam.atom_count}"
    ]

    %Paragraph{
      text: Enum.join(lines, "\n"),
      style: %Style{fg: :white},
      block: %Block{
        title: " BEAM ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }
  end

  defp footer_widget do
    %Paragraph{
      text: " q: quit  |  r: refresh",
      style: %Style{fg: :dark_gray},
      block: %Block{
        borders: [:top],
        border_style: %Style{fg: :dark_gray}
      }
    }
  end

  # -- Data collection --

  defp collect_stats(prev \\ %{}) do
    %{
      hostname: Map.get_lazy(prev, :hostname, &read_hostname/0),
      cpu_temp: read_cpu_temp(),
      memory: read_memory(),
      disk: read_disk(),
      interfaces: read_interfaces(),
      beam: read_beam_stats(),
      uptime_seconds: read_uptime()
    }
  end

  defp read_hostname do
    case File.read("/etc/hostname") do
      {:ok, name} -> String.trim(name)
      _ -> to_string(:net_adm.localhost())
    end
  end

  defp read_cpu_temp do
    case File.read("/sys/class/thermal/thermal_zone0/temp") do
      {:ok, content} ->
        content |> String.trim() |> String.to_integer() |> Kernel./(1000.0)

      _ ->
        nil
    end
  end

  defp read_memory do
    case File.read("/proc/meminfo") do
      {:ok, content} ->
        info =
          content
          |> String.split("\n", trim: true)
          |> Enum.reduce(%{}, fn line, acc ->
            case String.split(line, ~r/:\s+/) do
              [key, value | _] ->
                case Integer.parse(value) do
                  {kb, _} -> Map.put(acc, key, kb)
                  :error -> acc
                end

              _ ->
                acc
            end
          end)

        total = Map.get(info, "MemTotal", 0)
        available = Map.get(info, "MemAvailable", 0)
        used = total - available

        # Convert from kB to bytes for consistent formatting
        %{total: total * 1024, used: used * 1024}

      _ ->
        %{total: 0, used: 0}
    end
  end

  defp read_disk do
    output = :os.cmd(~c"df -k / 2>/dev/null") |> to_string()

    case String.split(output, "\n", trim: true) do
      [_header, data_line | _] ->
        case String.split(data_line, ~r/\s+/) do
          [_, total_str, used_str | _] ->
            total = String.to_integer(total_str) * 1024
            used = String.to_integer(used_str) * 1024
            %{total: total, used: used}

          _ ->
            %{total: 0, used: 0}
        end

      _ ->
        %{total: 0, used: 0}
    end
  rescue
    _ -> %{total: 0, used: 0}
  end

  defp read_interfaces do
    case :inet.getifaddrs() do
      {:ok, addrs} ->
        addrs
        |> Enum.flat_map(fn {name, opts} ->
          name_str = to_string(name)

          if name_str in ["lo", "lo0"] do
            []
          else
            ips =
              opts
              |> Keyword.get_values(:addr)
              |> Enum.filter(fn addr -> tuple_size(addr) == 4 end)
              |> Enum.map(&ip_to_string/1)

            case ips do
              [ip | _] -> [{name_str, ip}]
              [] -> [{name_str, "--"}]
            end
          end
        end)

      _ ->
        []
    end
  end

  defp read_beam_stats do
    mem = :erlang.memory()

    %{
      processes: :erlang.system_info(:process_count),
      ports: :erlang.system_info(:port_count),
      total_memory: Keyword.get(mem, :total, 0),
      process_memory: Keyword.get(mem, :processes_used, 0),
      ets_memory: Keyword.get(mem, :ets, 0),
      atom_count: :erlang.system_info(:atom_count)
    }
  end

  defp read_uptime do
    case File.read("/proc/uptime") do
      {:ok, content} ->
        content |> String.split(" ") |> List.first() |> String.to_float() |> trunc()

      _ ->
        # Fallback: BEAM uptime
        {uptime_ms, _} = :erlang.statistics(:wall_clock)
        div(uptime_ms, 1000)
    end
  end

  # -- Formatting helpers --

  defp format_uptime(seconds) do
    days = div(seconds, 86400)
    hours = div(rem(seconds, 86400), 3600)
    mins = div(rem(seconds, 3600), 60)

    cond do
      days > 0 -> "#{days}d #{hours}h #{mins}m"
      hours > 0 -> "#{hours}h #{mins}m"
      true -> "#{mins}m"
    end
  end

  defp format_mb(bytes) when is_integer(bytes) do
    (bytes / (1024 * 1024)) |> Float.round(1) |> to_string()
  end

  defp format_mb(_), do: "0"

  defp format_gb(bytes) when is_integer(bytes) do
    (bytes / (1024 * 1024 * 1024)) |> Float.round(1) |> to_string()
  end

  defp format_gb(_), do: "0"

  defp ip_to_string({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end
end

defmodule SystemMonitor.Runner do
  @moduledoc false

  def main(argv) do
    case argv do
      ["--ssh" | rest] -> run_ssh(rest)
      ["--distributed"] -> run_distributed()
      _ -> run_local()
    end
  end

  defp run_local do
    {:ok, pid} = SystemMonitor.start_link([])
    wait_for(pid)
  end

  defp run_ssh(rest) do
    port =
      case rest do
        [port_str] -> String.to_integer(port_str)
        _ -> 2222
      end

    {:ok, daemon} =
      ExRatatui.SSH.Daemon.start_link(
        mod: SystemMonitor,
        name: nil,
        port: port,
        system_dir: shared_host_key_dir(),
        auth_methods: ~c"password",
        user_passwords: [{~c"demo", ~c"demo"}]
      )

    IO.puts("""

    \e[36mSystem Monitor over SSH\e[0m — listening on port #{port}

    Connect from another terminal:

        ssh demo@localhost -p #{port}

    Password: \e[1mdemo\e[0m

    Ctrl-C twice to stop the daemon.
    """)

    wait_for(daemon)
  end

  defp run_distributed do
    unless Node.alive?() do
      IO.puts(:stderr, """

      \e[31mError:\e[0m This node is not distributed.
      Start it with --sname or --name:

          elixir --sname app --cookie demo -S mix run --no-halt \\
            examples/system_monitor.exs --distributed
      """)

      System.halt(1)
    end

    {:ok, pid} =
      ExRatatui.Distributed.Listener.start_link(mod: SystemMonitor)

    IO.puts("""

    \e[36mSystem Monitor over Erlang Distribution\e[0m

    This node: \e[1m#{Node.self()}\e[0m

    From another node (same cookie), run:

        ExRatatui.Distributed.attach(#{inspect(Node.self())}, SystemMonitor)

    Ctrl-C twice to stop the listener.
    """)

    wait_for(pid)
  end

  # Persist a throwaway host key under the system tmp dir so every
  # run doesn't leave a new fingerprint floating around. The
  # directory name is shared with the other ex_ratatui SSH examples
  # (e.g. the task_manager app) on purpose — switching from one
  # example to another on the same port would otherwise trip
  # `~/.ssh/known_hosts` with a "remote host identification has
  # changed" warning on every swap.
  #
  # We delegate the actual key generation to
  # `ExRatatui.SSH.Daemon.ensure_host_key!/1`, which handles the
  # idempotent first-boot creation and `0600` permissions for us. A
  # Phoenix or Mix application that wants this for free can pass
  # `auto_host_key: true` to the daemon instead — see the
  # `phoenix_ex_ratatui_example` repo for that flavour.
  defp shared_host_key_dir do
    [System.tmp_dir!(), "ex_ratatui_example_host_keys"]
    |> Path.join()
    |> ExRatatui.SSH.Daemon.ensure_host_key!()
  end

  defp wait_for(pid) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    end
  end
end

SystemMonitor.Runner.main(System.argv())
