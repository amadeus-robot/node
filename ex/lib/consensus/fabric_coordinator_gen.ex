defmodule FabricCoordinatorGen do
  use GenServer

  def isSyncing() do
    :persistent_term.get(FabricCoordinatorSyncing, false)
  end

  def start_link() do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  def precalc_sols(entry) do
    :erlang.spawn(fn()->
      Enum.each(entry.txs, fn(tx_packed)->
        isSol = String.contains?(tx_packed, "submit_sol")
        if isSol do
          txu = TX.unpack(tx_packed)
          [%{args: [sol]}] = txu.tx.actions

          :erlang.spawn(fn()->
            isVerified = :ets.lookup_element(SOLVerifyCache, sol, 2, nil)
            if !isVerified do
              :ets.insert(SOLVerifyCache, {sol, :inprogress})
              valid = BIC.Sol.verify(sol)
              if valid do
                :ets.insert(SOLVerifyCache, {sol, :valid})
              else
                :ets.insert(SOLVerifyCache, {sol, :invalid})
              end
            end
          end)

        end
      end)
    end)
  end

  def calc_syncing() do
    isSyncn = isSyncing()
    {_, num} = Process.info(self(), :message_queue_len)
    #IO.inspect num
    cond do
      num >= 10 and !isSyncn -> :persistent_term.put(FabricCoordinatorSyncing, true)
      num < 10 and isSyncn -> :persistent_term.put(FabricCoordinatorSyncing, false)
      true -> nil
    end
  end

  def handle_info({:insert_entry, entry, seen_time}, state) do
    calc_syncing()
    Fabric.insert_entry(entry, seen_time)
    precalc_sols(entry)
    {:noreply, state}
  end

  def handle_info({:validate_consensus, consensus}, state) do
    calc_syncing()
    :erlang.spawn(fn()->
      case Consensus.validate_vs_chain(consensus) do
        %{error: :ok, consensus: consensus} ->
          send(FabricCoordinatorGen, {:insert_consensus, consensus})
        _ -> nil
      end
    end)
    {:noreply, state}
  end

  def handle_info({:insert_consensus, consensus}, state) do
    calc_syncing()
    Fabric.insert_consensus(consensus)
    {:noreply, state}
  end

  def handle_info({:add_attestation, attestation}, state) do
    calc_syncing()

    Fabric.aggregate_attestation(attestation)

    #proc cached attestations
    ts_m = :os.system_time(1000)
    cached = :ets.select(AttestationCache, [{{{attestation.entry_hash, :_}, {:"$1", :_}}, [], [:"$1"]}])
    Enum.each(cached, fn(attestation)->
      Fabric.aggregate_attestation(attestation)
    end)
    if cached != [] do
      deleted = :ets.select_delete(AttestationCache, [{{{attestation.entry_hash, :_}, :_}, [], [true]}])
      #IO.inspect {:os.system_time(1000) - ts_m, length(cached), deleted, attestation.entry_hash |> Base58.encode()}
    end

    #clear stales
    case :ets.first_lookup(AttestationCache) do
      :'$end_of_table' -> nil
      {key, [{_, {_, ts_m_old}}]} ->
        delta = ts_m - ts_m_old
        if delta >= 10_000 do
          :ets.delete(AttestationCache, key)
        end
    end

    {:noreply, state}
  end
end
