defmodule SpecialMeetingAttestGen do
  use GenServer

  def isNextSlotStalled() do
    :persistent_term.get({SpecialMeeting, :nextSlotStalled}, nil)
  end

  def offlineTrainers() do
    :persistent_term.get({SpecialMeeting, :offlineTrainers}, [])
  end

  def start_link() do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    :erlang.send_after(6000, self(), :tick_stalled)
    :erlang.send_after(6000, self(), :tick_offline)
    {:ok, state}
  end

  def handle_info(:tick_stalled, state) do
    true && tick_stalled(state)
    :erlang.send_after(1000, self(), :tick_stalled)
    {:noreply, state}
  end

  def handle_info(:tick_offline, state) do
    true && tick_offline(state)
    :erlang.send_after(60_000, self(), :tick_offline)
    {:noreply, state}
  end

  def tick_stalled(state) do
    isSynced = FabricSyncGen.isQuorumSyncedOffBy1()

    entry = Consensus.chain_tip_entry()
    next_slot = entry.header_unpacked.slot + 1
    next_height = entry.header_unpacked.height + 1
    next_slot_trainer = Consensus.trainer_for_slot(next_height, next_slot)

    ts_m = :os.system_time(1000)
    seen_time = Fabric.entry_seentime(entry.hash)
    delta = ts_m - seen_time

    nextSlotStalled = :persistent_term.get({SpecialMeeting, :nextSlotStalled}, nil)

    #TODO: check for Slowloris
    #avg_seentimes_last_10_slots(malicious_pk) > 1second -> true

    #TODO: make this tighter later
    #no entry in 30seconds

    cond do
        !isSynced -> nil
        delta < 30_000 and nextSlotStalled -> :persistent_term.erase({SpecialMeeting, :nextSlotStalled})
        delta >= 30_000 and !nextSlotStalled -> :persistent_term.put({SpecialMeeting, :nextSlotStalled}, next_slot_trainer)
        true -> nil
    end
    #check for the last entry time, if we have not
    #had any new entries in the last X seconds
    #AND we are synced with the network
    #AND it is our timeround to call the meeting
    #WE call the special meeting to remove the malicious peer

    #IF a peer has not reached thier target slottime (we always
    #get late entries from the peer) RECORD
    #IF a peer is not producing an entry at all RECORD

    #WE can call the meeting and see if the peer consensus
    #agrees. This GenServer will be the local source of truth
  end

  def tick_offline(state) do
    isSynced = FabricSyncGen.isQuorumSyncedOffBy1()

    trainers = Consensus.trainers_for_height(Consensus.chain_height()+1)
    onlineTrainers = trainers
    |> Enum.filter(fn(pk)->
        p = NodePeers.by_pk(pk)
        cond do
          Application.fetch_env!(:ama, :trainer_pk) == pk -> true
          !!p and NodePeers.is_online(p) -> true
          true -> false
        end
    end)
    offlineTrainers = trainers -- onlineTrainers

    offlineLocal = Process.get(:offlineTrainersSeries, []) |> Enum.take(10)
    offlineLocal = [offlineTrainers] ++ offlineLocal
    Process.put(:offlineTrainersSeries, offlineLocal)

    offlinePTerm = :persistent_term.get({SpecialMeeting, :offlineTrainers}, [])

    xIntervalOffline = offlineLocal
    |> Enum.map(&MapSet.new/1)
    |> Enum.reduce(&MapSet.intersection/2)
    |> MapSet.to_list()
    |> Enum.sort()

    cond do
        !isSynced -> nil
        length(offlineLocal) < 10 -> nil
        offlinePTerm != xIntervalOffline -> :persistent_term.put({SpecialMeeting, :offlineTrainers}, xIntervalOffline)
        true -> nil
    end
  end

  def maybe_attest("slash_trainer_tx", epoch, malicious_pk) do
    slotStallTrainer = isNextSlotStalled()
    cond do
        byte_size(malicious_pk) != 48 -> nil
        Consensus.chain_epoch() != epoch -> nil

        #TODO: check for Slowloris
        #avg_seentimes_last_10_slots(malicious_pk) > 1second -> true

        malicious_pk == slotStallTrainer or malicious_pk in offlineTrainers()->
            msg = <<"slash_trainer", epoch::32-little, malicious_pk::binary>>
            sk = Application.fetch_env!(:ama, :trainer_sk)
            BlsEx.sign!(sk, msg, BLS12AggSig.dst_motion())

        true -> nil
    end
  end

  def maybe_attest("slash_trainer_entry", entry_packed) do
    slotStallTrainer = isNextSlotStalled()
    cur_entry = Consensus.chain_tip_entry()
    entry = Entry.unpack_and_validate(entry_packed)

    1 = length(entry.txs)
    tx = TX.unpack(hd(entry.txs))
    %{contract: "Epoch", function: "slash_trainer", args: args} = hd(tx.txu.actions)
    [epoch, malicious_pk, signature, mask_size, mask] = args
    <<mask::size(mask_size)-bitstring, _::bitstring>> = mask

    trainers = Consensus.trainers_for_height(entry.header_unpacked.height)

    cond do
        Consensus.chain_epoch() != epoch -> nil
        Entry.validate_next(cur_entry, entry) != %{error: :ok} -> nil
        BIC.Epoch.slash_trainer_verify(epoch, malicious_pk, trainers, mask, signature) != nil -> nil

        #TODO: check for Slowloris
        #avg_seentimes_last_10_slots(malicious_pk) > 1second -> true

        malicious_pk == slotStallTrainer or malicious_pk in offlineTrainers()->
          h = :erlang.term_to_binary(entry.header_unpacked, [:deterministic])
          sk = Application.fetch_env!(:ama, :trainer_sk)
          BlsEx.sign!(sk, Blake3.hash(h), BLS12AggSig.dst_entry())

        true -> nil
    end
  end
end