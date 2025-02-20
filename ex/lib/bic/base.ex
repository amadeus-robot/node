defmodule BIC.Base do
    import ConsensusKV

    def exec_cost(txu) do
        bytes = byte_size(txu.tx_encoded) + 32 + 96
        BIC.Coin.to_cents( 3 + div(bytes, 256) * 3 )
    end

    def can_pay_exec_cost(env) do
        BIC.Coin.balance(env.txu.tx.signer) >= exec_cost(env.txu)
    end

    def call_exit(env) do
        Process.delete(:mutations)
        Process.delete(:mutations_reverse)
        seed_random(env.entry.header_unpacked.vr, "", "")

        signer = env.entry.header_unpacked.signer

        #thank you come again
        kv_increment("bic:coin:balance:#{signer}", BIC.Coin.to_flat(1))

        if env.entry.header_unpacked.height >= 100_000 do
            if rem(env.entry.header_unpacked.height, 1000) == 0 do
                kv_put("bic:epoch:segment_vr", env.entry.header_unpacked.vr)
            end
        end

        cond do
            env.entry.header_unpacked.height == 0 ->
                kv_put("bic:epoch:trainers:0", [signer])
                kv_put("bic:epoch:pop:#{signer}", EntryGenesis.pop())
            rem(env.entry.header_unpacked.height, 100_000) == 99_999 ->
                BIC.Epoch.next(env)
            true -> :ok
        end

        {Process.get(:mutations, []), Process.get(:mutations_reverse, [])}
    end

    def call_tx_pre(env) do
        Process.delete(:mutations)
        Process.delete(:mutations_reverse)
        seed_random(env.entry.header_unpacked.vr, env.txu.hash, "")

        kv_put("bic:base:nonce:#{env.txu.tx.signer}", env.txu.tx.nonce)
        exec_cost = exec_cost(env.txu)
        kv_increment("bic:coin:balance:#{env.txu.tx.signer}", -exec_cost)
        kv_increment("bic:coin:balance:#{env.entry.header_unpacked.signer}", exec_cost)

        {Process.get(:mutations, []), Process.get(:mutations_reverse, [])}
    end

    def call_tx_actions(env) do
        Process.delete(:mutations)
        Process.delete(:mutations_reverse)

        result = try do
            call_tx_actions_1(env, 0)
            %{error: :ok}
        catch
            :throw,r -> r
            e,r ->
                IO.inspect {:tx_error, e, r, __STACKTRACE__}
                %{error: :unknown}
        end

        {Process.get(:mutations, []), Process.get(:mutations_reverse, []), result}
    end

    defp call_tx_actions_1(%{txu: %{tx: %{actions: []}}}, _idx) do nil end
    defp call_tx_actions_1(env = %{txu: %{tx: %{actions: [action|rest]}}}, action_index) do
        env = put_in(env, [:txu, :tx, :actions], rest)
        process_tx_2(env, action, "#{action_index}")
        call_tx_actions_1(env, action_index + 1)
    end

    defp seed_random(vr, txhash, action_index) do
        <<seed::256-little>> = Blake3.hash(<<vr::binary, txhash::binary, action_index::binary>>)
        :rand.seed(:exsss, seed)
    end

    defp process_tx_2(env, action, action_index) do
        seed_random(env.entry.header_unpacked.vr, env.txu.hash, action_index)
        module = String.to_existing_atom("Elixir.BIC.#{action.contract}")
        function = String.to_existing_atom(action.function)
        :erlang.apply(module, :call, [function, env, action.args])
    end
end