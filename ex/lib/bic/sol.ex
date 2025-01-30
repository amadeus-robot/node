defmodule BIC.Sol do
    import ConsensusKV
    
    def unpack(sol = <<epoch::32-little, _::binary>>) when epoch >= 1 do
        <<epoch::32-little, sol_pk::48-binary, pop::96-binary, computor_pk::48-binary, segment_vr::32-binary, _::binary>> = sol
        %{epoch: epoch, pk: sol_pk, pop: pop, computor: computor_pk, segment_vr: segment_vr}
    end
    def unpack(sol) do
        <<epoch::32-little, sol_pk::48-binary, pop::96-binary, computor_pk::48-binary, _::binary>> = sol
        %{epoch: epoch, pk: sol_pk, pop: pop, computor: computor_pk}
    end

    def verify_hash(epoch, hash) when epoch >= 1 do
        <<a, b, _::30-binary>> = hash
        a == 0 and b == 0
    end
    def verify(sol = <<epoch::32-little, _::192-binary, _segment_vr::32-binary, _::binary>>) when epoch >= 1 do
        #if !kv_get("bic:epoch:segment_vr:#{epoch}") == segment_vr, do: throw %{error: :segment_vr}
        verify_cache(UPOW1, sol)
    end

    def verify_hash(_epoch, hash) do
        <<a, _::31-binary>> = hash
        a == 0
    end
    def verify(sol = <<epoch::32-little, _::binary>>) do
        verify_cache(UPOW0, sol)
    end

    def verify_cache(module, sol = <<epoch::32-little, _::binary>>) do
        isVerified = :ets.lookup_element(SOLVerifyCache, sol, 2, nil)
        if isVerified == :valid do
            :ets.delete(SOLVerifyCache, sol)
            true
        else
            hash = module.calculate(sol)
            verify_hash(epoch, hash)
        end
    end
end