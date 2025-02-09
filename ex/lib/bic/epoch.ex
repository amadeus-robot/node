defmodule BIC.Epoch do
    import ConsensusKV

    @epoch_emission_base BIC.Coin.to_flat(1_000_000)
    @epoch_interval 100_000

    def epoch_emission(_epoch, acc \\ @epoch_emission_base)
    def epoch_emission(0, acc) do acc end
    def epoch_emission(epoch, acc) do
        sub = div(acc * 333, 1000000)
        epoch_emission(epoch - 1, acc - sub)
    end

    def circulating(_epoch, _acc \\ 0)
    def circulating(0, acc) do acc - BIC.Coin.burn_balance() end
    def circulating(epoch, acc) do
        circulating(epoch - 1, acc + epoch_emission(epoch))
    end

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
        epoch = Entry.epoch(env.entry)
        top_x = cond do
            epoch >= 3 -> 19
            true -> 9
        end

        leaders = kv_get_prefix("bic:epoch:solutions:")
        |> Enum.reduce(%{}, fn({_sol, pk}, acc)->
            Map.put(acc, pk, Map.get(acc, pk, 0) + 1)
        end)
        |> Enum.sort_by(& elem(&1,1), :desc)
        
        trainers = kv_get("bic:epoch:trainers:#{epoch}")
        trainers_to_recv_emissions = leaders
        |> Enum.filter(& elem(&1,0) in trainers)
        |> Enum.take(top_x)

        total_sols = Enum.reduce(trainers_to_recv_emissions, 0, & &2 + elem(&1,1))
        Enum.each(trainers_to_recv_emissions, fn({trainer, trainer_sols})->
            coins = div(trainer_sols * epoch_emission(epoch), total_sols)

            emission_address = kv_get("bic:epoch:emission_address:#{trainer}")
            if emission_address do
                kv_increment("bic:coin:balance:#{emission_address}", coins)
            else
                kv_increment("bic:coin:balance:#{trainer}", coins)
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
        kv_put("bic:epoch:trainers:#{epoch+1}", Enum.shuffle(new_trainers))
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