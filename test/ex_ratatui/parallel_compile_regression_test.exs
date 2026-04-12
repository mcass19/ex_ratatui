defmodule ExRatatui.ParallelCompileRegressionTest do
  use ExUnit.Case, async: false

  @tag :slow
  @tag timeout: 300_000
  test "isolated cold compiles do not crash compiler VMs in parallel" do
    repo_root = Path.expand("../..", __DIR__)

    temp_root =
      Path.join(
        System.tmp_dir!(),
        "ex_ratatui_parallel_compile_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(temp_root)
    File.mkdir_p!(temp_root)

    on_exit(fn -> File.rm_rf(temp_root) end)

    results =
      1..4
      |> Task.async_stream(
        fn index ->
          build_root = Path.join(temp_root, Integer.to_string(index))

          {output, status} =
            System.cmd(
              "mix",
              ["compile", "--warnings-as-errors"],
              cd: repo_root,
              env: [{"MIX_BUILD_PATH", Path.join(build_root, "build")}],
              stderr_to_stdout: true
            )

          %{index: index, status: status, output: output}
        end,
        max_concurrency: 4,
        ordered: false,
        timeout: 240_000
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> flunk("parallel compile task exited unexpectedly: #{inspect(reason)}")
      end)

    failures = Enum.reject(results, &(&1.status == 0))

    assert failures == [],
           "parallel cold compiles crashed:\n\n" <>
             Enum.map_join(failures, "\n\n", &format_failure/1)
  end

  defp format_failure(%{index: index, status: status, output: output}) do
    tail =
      output
      |> String.split("\n")
      |> Enum.take(-40)
      |> Enum.join("\n")

    "worker #{index} exited with status #{status}\n#{tail}"
  end
end
