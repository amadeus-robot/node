defmodule BIC.Epoch do
    import ConsensusKV

    @epoch_emission_base BIC.Coin.to_flat(1_000_000)
    @epoch_emission_fixed BIC.Coin.to_flat(100_000)
    @epoch_interval 100_000

    def epoch_emission(epoch) do
        epoch_emission_1(epoch) + @epoch_emission_fixed
    end

    defp epoch_emission_1(_epoch, acc \\ @epoch_emission_base)
    defp epoch_emission_1(0, acc) do acc end
    defp epoch_emission_1(epoch, acc) do
        sub = div(acc * 333, 1000000)
        emitted = acc - sub
        epoch_emission_1(epoch - 1, emitted)
    end

    def circulating_without_burn(_epoch, _acc \\ 0)
    def circulating_without_burn(0, acc) do acc end
    def circulating_without_burn(epoch, acc) do
        circulating_without_burn(epoch - 1, acc + epoch_emission(epoch))
    end

    def circulating(epoch) do circulating_without_burn(epoch) - BIC.Coin.burn_balance() end

    def call(:submit_sol, env, [sol]) do
        if kv_exists("bic:epoch:solutions:#{sol}"), do: throw(%{error: :sol_exists})
        
        if !BIC.Sol.verify(sol), do: throw(%{error: :invalid_sol})

        su = BIC.Sol.unpack(sol)
        if su.epoch != Entry.epoch(env.entry), do: throw(%{error: :invalid_epoch})

        if !kv_get("bic:epoch:pop:#{su.pk}") do
            if !BlsEx.verify?(su.pk, su.pop, su.pk, BLS12AggSig.dst_pop()), do: throw %{error: :invalid_pop}
            kv_put("bic:epoch:pop:#{su.pk}", su.pop)
        end
        kv_put("bic:epoch:solutions:#{sol}", su.pk)
    end

    def call(:set_emission_address, env, [address]) do
        if byte_size(address) != 48, do: throw(%{error: :invalid_address_pk})
        kv_put("bic:epoch:emission_address:#{env.txu.tx.signer}", address)
    end

    def next(env) do
        epoch_fin = Entry.epoch(env.entry)
        epoch_next = epoch_fin + 1
        top_x = cond do
            epoch_next > 38 -> 99
            epoch_next > 3 -> 19
            true -> 9
        end

        # slash sols for malicious trainers
        removedTrainers = kv_get("bic:epoch:trainers:removed:#{epoch_fin}")
        removedTrainers = if removedTrainers do :erlang.binary_to_term(removedTrainers, [:safe]) else [] end
        leaders = kv_get_prefix("bic:epoch:solutions:")
        |> Enum.reduce(%{}, fn({_sol, pk}, acc)->
            if pk in removedTrainers do
                acc
            else
                Map.put(acc, pk, Map.get(acc, pk, 0) + 1)
            end
        end)
        |> Enum.sort_by(& {elem(&1,1), elem(&1,0)}, :desc)
        
        trainers = kv_get("bic:epoch:trainers:#{epoch_fin}")
        trainers = if trainers do :erlang.binary_to_term(trainers, [:safe]) else [] end
        trainers_to_recv_emissions = leaders
        |> Enum.filter(& elem(&1,0) in trainers)
        |> Enum.take(top_x)

        total_sols = Enum.reduce(trainers_to_recv_emissions, 0, & &2 + elem(&1,1))
        Enum.each(trainers_to_recv_emissions, fn({trainer, trainer_sols})->
            coins = div(trainer_sols * epoch_emission(epoch_fin), total_sols)

            emission_address = kv_get("bic:epoch:emission_address:#{trainer}")
            if emission_address do
                kv_increment("bic:coin:balance:#{emission_address}:AMA", coins |> :erlang.integer_to_binary())
            else
                kv_increment("bic:coin:balance:#{trainer}:AMA", coins |> :erlang.integer_to_binary())
            end
        end)

        kv_clear("bic:epoch:solutions:")

        new_trainers = if length(leaders) == 0 do trainers else
            leaders = leaders
            |> Enum.take(top_x)
            |> Enum.map(fn{pk, _}-> pk end)
            
            #TODO: Even may not reach consensus in netsplit/malicicous net
            #TODO: but doubleslotting can potentially break other logic
            #if rem(length(leaders), 2) == 0 do
            #   leaders ++ [hd(leaders)]
            #else
            #   leaders
            #end
        end
        new_trainers = Enum.shuffle(new_trainers)
        kv_put("bic:epoch:trainers:#{epoch_next}", new_trainers |> :erlang.term_to_binary([:deterministic]))
        
        height = String.pad_leading("#{env.entry.header_unpacked.height+1}", 12, "0")
        kv_put("bic:epoch:trainers:height:#{height}", new_trainers |> :erlang.term_to_binary([:deterministic]))
    end

    def slash_trainer_verify(cur_epoch, malicious_pk, trainers, mask, signature) do
        signers = BLS12AggSig.unmask_trainers(trainers, mask)
        consensus_pct = length(signers) / length(trainers)

        apk = BlsEx.aggregate_public_keys!(signers)
        msg = <<"slash_trainer", cur_epoch::32-little, malicious_pk::binary>>
        validSignature = BlsEx.verify?(apk, signature, msg, BLS12AggSig.dst_motion())
        cond do
            consensus_pct < 0.75 -> :invalid_amount_of_signatures
            !validSignature -> :invalid_signature
            true -> nil
        end
    end

    def call(:slash_trainer, env, [epoch, malicious_pk, signature, mask_size, mask]) do
        epoch = if is_binary(epoch) do :erlang.binary_to_integer(epoch) else epoch end
        mask_size = if is_binary(mask_size) do :erlang.binary_to_integer(mask_size) else mask_size end

        cur_epoch = Entry.epoch(env.entry)
        <<mask::size(mask_size)-bitstring, _::bitstring>> = mask

        if cur_epoch != epoch, do: throw(%{error: :invalid_epoch})

        trainers = kv_get("bic:epoch:trainers:#{cur_epoch}")
        trainers = if trainers do :erlang.binary_to_term(trainers, [:safe]) else [] end
        if malicious_pk not in trainers, do: throw(%{error: :invalid_trainer_pk})

        # 75% vote
        signers = BLS12AggSig.unmask_trainers(trainers, mask)
        consensus_pct = length(signers) / length(trainers)
        if consensus_pct < 0.75, do: throw %{error: :invalid_amount_of_signatures}

        apk = BlsEx.aggregate_public_keys!(signers)
        msg = <<"slash_trainer", cur_epoch::32-little, malicious_pk::binary>>
        if !BlsEx.verify?(apk, signature, msg, BLS12AggSig.dst_motion()), do: throw %{error: :invalid_signature}

        removed = kv_get("bic:epoch:trainers:removed:#{cur_epoch}")
        removed = if removed do :erlang.binary_to_term(removed, [:safe]) else [] end
        kv_put("bic:epoch:trainers:removed:#{cur_epoch}", (removed ++ [malicious_pk]) |> :erlang.term_to_binary([:deterministic]))

        new_trainers = trainers -- [malicious_pk]
        kv_put("bic:epoch:trainers:#{cur_epoch}", new_trainers |> :erlang.term_to_binary([:deterministic]))

        height = String.pad_leading("#{env.entry.header_unpacked.height+1}", 12, "0")
        kv_put("bic:epoch:trainers:height:#{height}", new_trainers |> :erlang.term_to_binary([:deterministic]))
    end

    @doc """
    def call(:slash_double_entry, env, [entrya, entryb]) do
        %{trainer: trainera, height: heighta, hash: hasha} = entrychain.validate_entry(entrya)
        %{trainer: trainerb, height: heightb, hash: hashb} = entrychain.validate_entry(entryb)

        if trainera != trainerb, do: throw(%{error: :different_signer})
        if heighta != heightb, do: throw(%{error: :different_height})
        if trunc(heighta/100_000) != trunc(env.height/100_000), do: throw(%{error: :stale_chain_epoch})
        if hasha == hashb, do: throw(%{error: :same_entry})

        kv_delete(:trainers, trainera)
        kv_delete_match(:solutions, {:_, %{trainer: trainera}})
    end
    """
end