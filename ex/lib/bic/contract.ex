defmodule BIC.Contract do
    import ConsensusKV

    def validate(wasmbytes, env \\ nil) do
        env = if env do Map.put(env, :readonly, true) else
            env = Consensus.make_mapenv(EntryGenesis.get())

            Map.merge(env, %{
                readonly: true,
                seed: :crypto.strong_rand_bytes(32),
                tx_index: 0,
                tx_signer: :crypto.strong_rand_bytes(48),
                tx_nonce: :os.system_time(:nanosecond),
                tx_hash: :crypto.strong_rand_bytes(32),
                account_origin: :crypto.strong_rand_bytes(48),
                account_caller: :crypto.strong_rand_bytes(48),
                account_current: :crypto.strong_rand_bytes(48),
                attached_symbol: "",
                attached_amount: "",
            })
        end
        try do
            case WasmerEx.validate_contract(env, wasmbytes) do
                :ok -> %{error: :ok}
                {:error, reason} -> %{error: :abort, reason: reason}
            end
        catch
            _,_ -> %{error: :system}
        end
    end

    def bytecode(account) do
        kv_get("bic:contract:account:#{account}:bytecode")
    end

    def call(:deploy, env, [wasmbytes]) do
        kv_put("bic:contract:account:#{env.account_caller}:bytecode", wasmbytes)
    end
end
