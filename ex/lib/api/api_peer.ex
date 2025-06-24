defmodule API.Peer do
    def trainers() do
        Consensus.trainers_for_height(Consensus.chain_height()+1)
        |> Enum.map(fn(pk)->
            p = NodePeers.by_pk(pk)
            inSlot = Consensus.trainer_for_slot(Consensus.chain_height()+1, Consensus.chain_height()+1) == pk
            if !!p and NodePeers.is_online(p) do
                [Base58.encode(pk), p[:version], true, inSlot, p[:latency], Base58.encode(get_in(p, [:temporal, :hash])), get_in(p, [:temporal, :header_unpacked, :height]), get_in(p, [:rooted, :header_unpacked, :height])]
            else
                [Base58.encode(pk), p[:version], false, inSlot]
            end
        end)
        |> Enum.sort_by(& Enum.at(&1,1), :desc)
    end

    def version_ratio() do
        trainers = trainers()
        trainers
        |> Enum.reduce(%{}, fn([_pk, version | _], acc)->
            Map.put(acc, version, Map.get(acc, version, 0) + 1)
        end)
        |> Enum.sort_by(& elem(&1, 1), :desc)
        |> Enum.map(fn({version, cnt})->
            {version, cnt, Float.round(cnt/length(trainers), 3)}
        end)
    end

    def all_for_web() do
        trainers = Consensus.trainers_for_height(Consensus.chain_height()+1)
        NodePeers.all()
        |> Enum.filter(& !!&1[:pk] and !!&1[:version])
        |> Enum.map(& %{
            pk: Base58.encode(&1[:pk]),
            version: &1[:version],
            latency: &1[:latency] || 0,
            is_trainer: &1[:pk] in trainers,
            temporal_height: get_in(&1, [:temporal, :header_unpacked, :height]),
            rooted_height: get_in(&1, [:rooted, :header_unpacked, :height])
        })
        |> Enum.sort_by(& &1.temporal_height, :desc)
    end

    def all_trainers() do
        all_for_web()
        |> Enum.filter(& &1.is_trainer)
        |> Enum.map(fn(map)->
            Map.put(map, :slot_speed, SpecialMeetingAttestGen.calcSlow(Base58.decode(map.pk)))
        end)
    end

    def removed_trainers(epoch \\ nil) do
        epoch = if !epoch do Consensus.chain_epoch() else epoch end
        trainers_for_epoch = Consensus.trainers_for_height(epoch*100_000)
        trainers = Consensus.trainers_for_height(Consensus.chain_height()+1)
        (trainers_for_epoch -- trainers)
        |> Enum.map(& Base58.encode(&1))
    end

    def all() do
        NodePeers.all()
        |> Enum.map(& [
            &1[:version],&1[:latency],Base58.encode(&1[:pk]),
            get_in(&1, [:temporal, :header_unpacked, :height]),
            get_in(&1, [:rooted, :header_unpacked, :height]),
        ])
        |> Enum.sort(:desc)
    end
end
