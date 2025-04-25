defmodule SpecialMeetingGen do
  use GenServer

  def try_slash_trainer_entry_next() do
    if SpecialMeetingAttestGen.isNextSlotStalled() do
      mpk = Consensus.trainer_for_slot_next()
      send(SpecialMeetingGen, {:try_slash_trainer_entry, mpk})
    end
  end

  def try_slash_trainer_entry(mpk) do
    slow = !!SpecialMeetingAttestGen.calcSlow(mpk) and SpecialMeetingAttestGen.calcSlow(mpk) > 600
    if !!SpecialMeetingAttestGen.isNextSlotStalled() or slow do
      send(SpecialMeetingGen, {:try_slash_trainer_entry, mpk})
    end
  end

  def try_slash_trainer_tx(mpk) do
    slow = !!SpecialMeetingAttestGen.calcSlow(mpk) and SpecialMeetingAttestGen.calcSlow(mpk) > 600
    if !!SpecialMeetingAttestGen.isNextSlotStalled() or slow do
      send(SpecialMeetingGen, {:try_slash_trainer_tx, mpk})
    end
  end

  def start_link() do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    :erlang.send_after(8000, self(), :tick)
    {:ok, state}
  end

  def handle_info(:tick, state) do
    state = tick(state)
    :erlang.send_after(1000, self(), :tick)
    {:noreply, state}
  end

  def handle_info({:try_slash_trainer_entry, mpk}, state) do
    slash_trainer = build_slash_tx_business(mpk)
    state = put_in(state, [:slash_trainer], slash_trainer)
    state = put_in(state, [:slash_trainer, :type], :entry)
    state = put_in(state, [:slash_trainer, :state], :gather_tx_sigs)
    state = put_in(state, [:slash_trainer, :attempts], 0)
    state = put_in(state, [:slash_trainer, :score_tx], 0)
    state = put_in(state, [:slash_trainer, :score_entry], 0)
    {:noreply, state}
  end

  def handle_info({:try_slash_trainer_tx, mpk}, state) do
    slash_trainer = build_slash_tx_business(mpk)
    state = put_in(state, [:slash_trainer], slash_trainer)
    state = put_in(state, [:slash_trainer, :type], :tx)
    state = put_in(state, [:slash_trainer, :state], :gather_tx_sigs)
    state = put_in(state, [:slash_trainer, :attempts], 0)
    state = put_in(state, [:slash_trainer, :score_tx], 0)
    state = put_in(state, [:slash_trainer, :score_entry], 0)
    {:noreply, state}
  end

  def handle_info({:add_slash_trainer_tx_reply, pk, signature}, state = %{slash_trainer: _}) do
    st = state.slash_trainer
    trainers = Consensus.trainers_for_height(st.height + 1)
    ma = BLS12AggSig.add(%{mask: st.mask, aggsig: st.aggsig}, trainers, pk, signature)
    state = put_in(state, [:slash_trainer, :mask], ma.mask)
    state = put_in(state, [:slash_trainer, :aggsig], ma.aggsig)

    score = BLS12AggSig.score(trainers, state.slash_trainer.mask)
    state = put_in(state, [:slash_trainer, :score_tx], score)

    {:noreply, state}
  end

  def handle_info({:add_slash_trainer_entry_reply, entry_hash, pk, signature}, state = %{slash_trainer: _}) do
    entry = state.slash_trainer.entry
    true = entry.hash == entry_hash

    trainers = Consensus.trainers_for_height(entry.header_unpacked.height + 1)
    ma = BLS12AggSig.add(%{mask: entry.mask, aggsig: entry.signature}, trainers, pk, signature)
    state = put_in(state, [:slash_trainer, :entry, :mask], ma.mask)
    state = put_in(state, [:slash_trainer, :entry, :signature], ma.aggsig)

    score = BLS12AggSig.score(trainers, state.slash_trainer.entry.mask)
    state = put_in(state, [:slash_trainer, :score_entry], score)

    {:noreply, state}
  end

  def tick(state) do
    my_pk = Application.fetch_env!(:ama, :trainer_pk)
    height = Consensus.chain_height()
    trainers = Consensus.trainers_for_height(height + 1)

    #IO.inspect state[:slash_trainer]

    cond do
      my_pk not in trainers -> state
      !state[:slash_trainer] -> state
      state.slash_trainer.attempts > 6 -> Map.delete(state, :slash_trainer)
      
      state.slash_trainer.type == :tx and state.slash_trainer[:score_tx] >= 0.75 ->
        tx_packed = build_slash_tx(state.slash_trainer)
        IO.inspect tx_packed
        TXPool.insert(tx_packed)
        NodeGen.broadcast(:txpool, :trainers, [[tx_packed]])
        Map.delete(state, :slash_trainer)
      state.slash_trainer.type == :entry and state.slash_trainer.state == :gather_tx_sigs and state.slash_trainer[:score_tx] >= 0.75 ->
        entry = build_slash_entry(state.slash_trainer)
        state = put_in(state, [:slash_trainer, :entry], entry)
        put_in(state, [:slash_trainer, :state], :gather_entry_sigs)
      state.slash_trainer.state == :gather_tx_sigs ->
        business = %{op: "slash_trainer_tx", epoch: state.slash_trainer.epoch, malicious_pk: state.slash_trainer.malicious_pk}
        NodeGen.broadcast(:special_business, :trainers, [business])
        put_in(state, [:slash_trainer, :attempts], state.slash_trainer.attempts + 1)

      state.slash_trainer.type == :entry and state.slash_trainer[:score_entry] >= 0.75 ->
        IO.inspect {:entry_with_score, state.slash_trainer[:score_entry]}
        IO.inspect state.slash_trainer.entry, limit: 1111111111, printable_limit: 1111111111
        Fabric.insert_entry(state.slash_trainer.entry, :os.system_time(1000))
        Map.delete(state, :slash_trainer)
      state.slash_trainer.state == :gather_entry_sigs ->
        business = %{op: "slash_trainer_entry", entry_packed: Entry.pack(state.slash_trainer.entry)}
        NodeGen.broadcast(:special_business, :trainers, [business])
        put_in(state, [:slash_trainer, :attempts], state.slash_trainer.attempts + 1)

      true ->
        IO.inspect {:fin, state.slash_trainer}
        state
    end
  end

  def build_slash_tx_business(mpk) do
    height = Consensus.chain_height()
    epoch = Consensus.chain_epoch()
    trainers = Consensus.trainers_for_height(height+1)
    my_pk = Application.fetch_env!(:ama, :trainer_pk)

    signature = SpecialMeetingAttestGen.maybe_attest("slash_trainer_tx", epoch, mpk)
    
    ma = BLS12AggSig.new(trainers, my_pk, signature)
    %{height: height, malicious_pk: mpk, epoch: epoch, mask: ma.mask, aggsig: ma.aggsig}
  end

  def build_slash_tx(st) do
    my_pk = Application.fetch_env!(:ama, :trainer_pk)
    my_sk = Application.fetch_env!(:ama, :trainer_sk)
    TX.build(my_sk, "Epoch", "slash_trainer", 
      ["#{st.epoch}", st.malicious_pk, st.aggsig, "#{bit_size(st.mask)}", Util.pad_bitstring_to_bytes(st.mask)],
      Consensus.chain_nonce(my_pk)+1)
  end

  def build_slash_entry(st) do
    my_pk = Application.fetch_env!(:ama, :trainer_pk)
    packed_tx = build_slash_tx(st)

    true = FabricSyncAttestGen.isQuorumSynced()
    cur_entry = Consensus.chain_tip_entry()
    cur_height = cur_entry.header_unpacked.height
    cur_slot = cur_entry.header_unpacked.slot

    next_entry = Entry.build_next(cur_entry, cur_slot + 1)
    txs = [packed_tx]
    next_entry = Map.put(next_entry, :txs, txs)
    next_entry = Entry.sign(next_entry)
    
    trainers = Consensus.trainers_for_height(next_entry.header_unpacked.height + 1)
    mask = <<0::size(length(trainers))>>
    mask = Util.set_bit(mask, Util.index_of(trainers, my_pk))
    Map.put(next_entry, :mask, mask)
  end

  def my_tickslice() do
    pk = Application.fetch_env!(:ama, :trainer_pk)
    entry = Consensus.chain_tip_entry()

    my_height = entry.header_unpacked.height
    slot = entry.header_unpacked.slot
    next_slot = slot + 1
    next_height = my_height + 1

    trainers = Consensus.trainers_for_height(next_height + 1)
    #TODO: make this 3 or 6 later
    ts_s = :os.system_time(1)
    sync_round_offset = rem(div(ts_s, 60), length(trainers))
    sync_round_index = Enum.find_index(trainers, fn t -> t == pk end)

    seconds_in_minute = rem(ts_s, 60)

    sync_round_offset == sync_round_index 
    and seconds_in_minute >= 10
    and seconds_in_minute <= 50
  end

  def check(business) do
    if check_business(business) do

    end
  end

  def check_business(business = %{op: "slash_trainer", malicious_pk: malicious_pk}) do
    slotStallTrainer = SpecialMeetingAttestGen.isNextSlotStalled()

    cond do
        byte_size(malicious_pk) != 48 -> false

        #TODO: check for Slowloris
        #avg_seentimes_last_10_slots(malicious_pk) > 1second -> true

        malicious_pk == slotStallTrainer -> true

        true -> false
    end
  end
end