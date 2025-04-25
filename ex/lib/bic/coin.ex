defmodule BIC.Coin do
    import ConsensusKV

    @decimals 9
    @burn_address :binary.copy(<<0>>, 48)

    def to_flat(coins) when is_integer(coins) do
        coins * 1_000_000_000
    end

    def to_cents(coins) when is_integer(coins) do
        coins *    10_000_000
    end

    def to_tenthousandth(coins) when is_integer(coins) do
        coins *       100_000
    end

    def from_flat(coins) do
        Float.round(coins / 1_000_000_000, 9)
    end

    def burn_address() do
        @burn_address
    end

    def burn_balance(symbol \\ "AMA") do
        balance(@burn_address)
    end

    def balance(pubkey, symbol \\ "AMA") do
        case kv_get("bic:coin:balance:#{pubkey}:#{symbol}") do
            nil -> 0
            value -> :erlang.binary_to_integer(value)
        end
    end

    def call(:transfer, env, [symbol, receiver, amount]) do
        if byte_size(receiver) != 48, do: throw(%{error: :invalid_receiver_pk})
        amount = if is_binary(amount) do :erlang.binary_to_integer(amount) else amount end
        if !is_integer(amount), do: throw(%{error: :invalid_amount})
        if amount <= 0, do: throw(%{error: :invalid_amount})
        if amount > balance(env.txu.tx.signer, symbol), do: throw(%{error: :insufficient_funds})

        kv_increment("bic:coin:balance:#{env.txu.tx.signer}:#{symbol}", -amount |> :erlang.integer_to_binary())
        kv_increment("bic:coin:balance:#{receiver}:#{symbol}", amount |> :erlang.integer_to_binary())
    end
end
