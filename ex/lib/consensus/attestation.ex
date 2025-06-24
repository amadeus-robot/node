defmodule Attestation do
    @doc """
    attestation {
        entry_hash: <>,
        mutations_hash: <>,
        signer: <>,
        signature: <entry_hash,mutations_hash>,
    }
    """
    def unpack(attestation_packed) when is_binary(attestation_packed) do
        a = :erlang.binary_to_term(attestation_packed, [:safe])
        unpack(a)
    end
    def unpack(attestation_packed) when is_map(attestation_packed) do
        Map.take(attestation_packed, [:entry_hash, :mutations_hash, :signer, :signature])
    end
    def unpack(nil), do: nil


    def pack(attestation_unpacked) when is_binary(attestation_unpacked) do attestation_unpacked end
    def pack(attestation_unpacked) do
        attestation_unpacked
        |> Map.take([:entry_hash, :mutations_hash, :signer, :signature])
        |> :erlang.term_to_binary([:deterministic])
    end

    def sign(entry_hash, mutations_hash) do
        pk = Application.fetch_env!(:ama, :trainer_pk)
        sk = Application.fetch_env!(:ama, :trainer_sk)
        signature = BlsEx.sign!(sk, <<entry_hash::binary, mutations_hash::binary>>, BLS12AggSig.dst_att())
        %{
            entry_hash: entry_hash,
            mutations_hash: mutations_hash,
            signer: pk,
            signature: signature,
        }
    end

    def unpack_and_validate(attestation_packed) do
        try do
        attestation_size = Application.fetch_env!(:ama, :attestation_size)
        if byte_size(attestation_packed) >= attestation_size, do: throw(%{error: :too_large})
        a = :erlang.binary_to_term(attestation_packed, [:safe])
        |> Map.take([:entry_hash, :mutations_hash, :signer, :signature])
        if attestation_packed != :erlang.term_to_binary(a, [:deterministic]), do: throw %{error: :not_deterministicly_encoded}

        res = validate(a)
        cond do
            res.error != :ok -> throw res
            true -> %{error: :ok, attestation: a}
        end
        catch
            :throw,r -> r
            e,r -> IO.inspect {Attestation, :unpack_and_validate, e, r, __STACKTRACE__}; %{error: :unknown}
        end
    end

    def validate(a) do
        try do
        if !is_binary(a.entry_hash), do: throw(%{error: :entry_hash_not_binary})
        if byte_size(a.entry_hash) != 32, do: throw(%{error: :entry_hash_not_256_bits})
        if !is_binary(a.mutations_hash), do: throw(%{error: :mutations_hash_not_binary})
        if byte_size(a.mutations_hash) != 32, do: throw(%{error: :mutations_hash_not_256_bits})
        if !is_binary(a.signer), do: throw(%{error: :signer_not_binary})
        if byte_size(a.signer) != 48, do: throw(%{error: :signer_not_48_bytes})

        bin = <<a.entry_hash::binary, a.mutations_hash::binary>>
        if !BlsEx.verify?(a.signer, a.signature, bin, BLS12AggSig.dst_att()), do: throw(%{error: :invalid_signature})

        %{error: :ok}
        catch
            :throw,r -> r
            e,r -> IO.inspect {Attestation, :validate, e, r}; %{error: :unknown}
        end
    end

    def validate_vs_chain(a) do
        entry = Fabric.entry_by_hash(a.entry_hash)
        chain_height = Consensus.chain_height()
        if !!entry and entry.header_unpacked.height <= Consensus.chain_height() do
            trainers = Consensus.trainers_for_height(Entry.height(entry))
            if !!trainers and a.signer in trainers do
                true
            end
        end
    end
end
