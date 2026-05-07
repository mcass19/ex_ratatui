defmodule ExRatatui.Property.IntentsPropertyTest do
  @moduledoc """
  Property-based invariants for the `:intents` runtime opt under the
  4-tuple `{:cell_session, cs, cell_writer_fn, intent_writer_fn}`
  transport tag.

  Complements the unit tests in `ExRatatui.Server.IntentsTest`, which
  pin specific scenarios (mount-time, handle_event, handle_info,
  stop-with-intent, drop-without-writer, shape validation). These
  properties pin the ordering + volume invariants the unit tests
  imply but never explicitly stress with generated input:

    1. **Order preservation across batches.** For any mount-intent
       list and any sequence of `handle_info`-supplied batches, the
       writer receives every intent in concat order with no
       reordering, no drops, and no extras.

    2. **Empty batches are no-ops.** A `handle_info` that returns
       `intents: []` fires nothing on the writer.

  Together with the unit tests these cover the full intent contract.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ExRatatui.CellSession
  alias ExRatatui.Test.ServerApps.Intents

  property "intents from mount + N handle_info batches reach the writer in concat order" do
    check all(
            mount_batch <- intent_list(),
            info_batches <- StreamData.list_of(intent_list(), max_length: 4)
          ) do
      {pid, cleanup} = start_intents_server(mount_intents: mount_batch)
      assert_receive {:mounted, _opts}, 500

      try do
        # 1. Mount intents fire first, in original order.
        for intent <- mount_batch do
          assert_receive {:writer_intent, ^intent}, 500
        end

        # 2. Each handle_info batch — runs sequentially because the
        # GenServer processes mailbox messages one at a time.
        for batch <- info_batches do
          send(pid, {:emit_intents, batch})

          for intent <- batch do
            assert_receive {:writer_intent, ^intent}, 500
          end
        end

        # 3. No stragglers — the writer gets exactly what was emitted,
        # nothing else.
        refute_received {:writer_intent, _}
      after
        cleanup.()
      end
    end
  end

  property "empty intents lists don't fire on the writer" do
    check all(empty_calls <- StreamData.integer(0..5)) do
      {pid, cleanup} = start_intents_server(mount_intents: [])
      assert_receive {:mounted, _opts}, 500

      try do
        # Drive `empty_calls` empty batches. Each is processed
        # synchronously by the GenServer loop; the trailing
        # `:sys.get_state/1` flushes the mailbox so we know every batch
        # has been fully handled — and none of them should have
        # produced a writer message.
        for _ <- 1..empty_calls//1 do
          send(pid, {:emit_intents, []})
        end

        _ = :sys.get_state(pid)

        refute_received {:writer_intent, _}
      after
        cleanup.()
      end
    end
  end

  ## Helpers

  defp start_intents_server(opts) do
    cs = CellSession.new(20, 5)
    parent = self()

    cell_writer = fn _diff -> :ok end
    intent_writer = fn intent -> send(parent, {:writer_intent, intent}) end

    {:ok, pid} =
      ExRatatui.Server.start_link(
        Keyword.merge(
          [
            mod: Intents,
            name: nil,
            test_pid: parent,
            transport: {:cell_session, cs, cell_writer, intent_writer}
          ],
          opts
        )
      )

    cleanup = fn -> if Process.alive?(pid), do: GenServer.stop(pid) end
    {pid, cleanup}
  end

  defp intent_list do
    StreamData.list_of(intent_term(), max_length: 4)
  end

  defp intent_term do
    # Tuples of {atom, string} are interesting enough to catch
    # ordering bugs while keeping shrinkage readable. ex_ratatui
    # treats them as opaque so any term would work.
    StreamData.tuple({
      StreamData.atom(:alphanumeric),
      StreamData.string(:alphanumeric, max_length: 8)
    })
  end
end
