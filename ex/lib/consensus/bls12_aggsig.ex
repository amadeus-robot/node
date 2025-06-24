defmodule BLS12AggSig do
    @dst "AMADEUS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_NUL_"
    @dst_pop "AMADEUS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_"
    @dst_att "AMADEUS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_ATTESTATION_"
    @dst_entry "AMADEUS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_ENTRY_"
    @dst_vrf "AMADEUS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_VRF_"
    @dst_tx "AMADEUS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_TX_"
    @dst_motion "AMADEUS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_MOTION_"
    @dst_node "AMADEUS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_NODE_"

    def dst(), do: @dst
    def dst_pop(), do: @dst_pop
    def dst_att(), do: @dst_att
    def dst_entry(), do: @dst_entry
    def dst_vrf(), do: @dst_vrf
    def dst_tx(), do: @dst_tx
    def dst_motion(), do: @dst_motion
    def dst_node(), do: @dst_node

    def new(trainers, pk, signature) do
        index_of_trainer = Util.index_of(trainers, pk)

        mask = <<0::size(length(trainers))>>
        mask = Util.set_bit(mask, index_of_trainer)

        %{mask: mask, aggsig: signature}
    end

    def add(m = %{mask: mask, aggsig: aggsig}, trainers, pk, signature) do
        index_of_trainer = Util.index_of(trainers, pk)

        if Util.get_bit(mask, index_of_trainer) do m else
            mask = Util.set_bit(mask, index_of_trainer)
            aggsig = BlsEx.aggregate_signatures!([aggsig, signature])
            %{mask: mask, aggsig: aggsig}
        end
    end

    #TODO: optimize walking with mask
    def unmask_trainers(trainers, mask) do
        length = bit_size(mask)
        Enum.reduce(0..length-1, [], fn(index, acc)->
            if !Util.get_bit(mask, index) do acc else
                acc ++ [Enum.at(trainers, index)]
            end
        end)
    end

    def score(trainers, mask) do
        trainers_signed = unmask_trainers(trainers, mask)

        maxScore = length(trainers)
        score = Enum.reduce(trainers_signed, 0, fn(pk, acc)->
            acc + ConsensusWeight.count(pk)
        end)
        score/maxScore
    end
end
