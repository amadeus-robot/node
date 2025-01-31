defmodule TX do
   @doc """
   %{
     tx: %{
      signer: Base58PK,
      nonce: :os.system_time(:nanosecond),
      actions: [%{op: "call", contract: "", function: "", args: []}]
     },
     tx_encoded: <<>>,
     hash: <<>>,
     signature: <<>>
   }
   """

   def normalize_atoms(txu) do
      t = %{
         tx_encoded: Map.fetch!(txu, "tx_encoded"),
         hash: Map.fetch!(txu, "hash"),
         signature: Map.fetch!(txu, "signature")
      }
      if !txu["tx"] do t else
          tx = Map.fetch!(txu, "tx")
          actions = Map.fetch!(tx, "actions")
          actions = Enum.map(actions, fn %{"op"=> o, "contract"=> c, "function"=> f, "args"=> a} -> 
            %{op: o, contract: c, function: f, args: a}
          end)
          tx = %{signer: Map.fetch!(tx, "signer"), nonce: Map.fetch!(tx, "nonce"), actions: actions}
          Map.put(t, :tx, tx)
      end
   end

   def validate(tx_packed) do
      try do
         tx_size = Application.fetch_env!(:ama, :tx_size)
       if byte_size(tx_packed) >= tx_size, do: throw(%{error: :too_large})

      txu = VanillaSer.decode!(tx_packed)
      txu = Map.take(txu, ["tx_encoded", "hash", "signature"])
      tx_encoded = Map.fetch!(txu, "tx_encoded")
      tx = VanillaSer.decode!(tx_encoded)
      tx = Map.take(tx, ["signer", "nonce", "actions"])
      actions = Enum.map(Map.fetch!(tx, "actions"), & Map.take(&1, ["op", "contract", "function", "args"]))
      tx = Map.put(tx, "actions", actions)
      txu = Map.put(txu, "tx", tx)
      hash = Map.fetch!(txu, "hash")
      signature = Map.fetch!(txu, "signature")
      txu = normalize_atoms(txu)

      canonical = VanillaSer.encode(%{tx_encoded: VanillaSer.encode(tx), hash: hash, signature: signature})
      if tx_packed != canonical, do: throw(%{error: :tx_not_canonical})

      if hash != Blake3.hash(tx_encoded), do: throw(%{error: :invalid_hash})
      if !BlsEx.verify?(txu.tx.signer, signature, hash, BLS12AggSig.dst_tx()), do: throw(%{error: :invalid_signature})

      if !is_integer(txu.tx.nonce), do: throw(%{error: :nonce_not_integer})
      if !is_list(txu.tx.actions), do: throw(%{error: :actions_must_be_list})
      if length(txu.tx.actions) != 1, do: throw(%{error: :actions_length_must_be_1})
      action = hd(txu.tx.actions)
      if action[:op] != "call", do: throw %{error: :op_must_be_call}
      if !is_binary(action[:contract]), do: throw %{error: :contract_must_be_binary}
      if !is_binary(action[:function]), do: throw %{error: :function_must_be_binary}
      if !is_list(action[:args]), do: throw %{error: :args_must_be_list}
      Enum.each(action.args, fn(arg)->
         if !is_integer(arg) and !is_binary(arg), do: throw(%{error: :arg_invalid_type})
      end)
      if !:lists.member(action.contract, ["Epoch", "Coin"]), do: throw %{error: :invalid_module}
      if !:lists.member(action.function, ["submit_sol", "transfer", "set_emission_address"]), do: throw %{error: :invalid_function}

      #if !!txp.tx[:delay] and !is_integer(txp.tx.delay), do: throw %{error: :delay_not_integer}
      #if !!txp.tx[:delay] and txp.tx.delay <= 0, do: throw %{error: :delay_too_low}
      #if !!txp.tx[:delay] and txp.tx.delay > 100_000, do: throw %{error: :delay_too_hi}

      throw %{error: :ok, txu: txu}
      catch
         :throw,r -> r
         e,r ->
             IO.inspect {TX, :validate, e, r}
            %{error: :unknown}
      end
   end

   def build(sk, contract, function, args) do
      pk = BlsEx.get_public_key!(sk)
      action = %{op: "call", contract: contract, function: function, args: args}
      tx_encoded = %{
         signer: pk,
         nonce: :os.system_time(:nanosecond),
         actions: [action]
      }
      |> VanillaSer.encode()
      hash = Blake3.hash(tx_encoded)
      signature = BlsEx.sign!(sk, hash, BLS12AggSig.dst_tx())
      VanillaSer.encode(%{tx_encoded: tx_encoded, hash: hash, signature: signature})
   end

   def chain_valid(tx_packed) when is_binary(tx_packed) do chain_valid(TX.unpack(tx_packed)) end
   def chain_valid(txu) do
      #TODO: once more than 1 tx allowed per entry fix this
      chainNonce = Consensus.chain_nonce(txu.tx.signer)
      nonceValid = !chainNonce or txu.tx.nonce > chainNonce
      hasBalance = BIC.Base.exec_cost(txu) <= Consensus.chain_balance(txu.tx.signer)

      hasSol = Enum.find_value(txu.tx.actions, fn(a)-> a.function == "submit_sol" and hd(a.args) end)
      epochSolValid = if !hasSol do true else
         <<sol_epoch::32-little, _::binary>> = hasSol
         Consensus.chain_epoch() == sol_epoch
      end

      cond do
         !epochSolValid -> false
         !nonceValid -> false
         !hasBalance -> false
         true -> true
      end
   end

    def pack(txu) do
      txu = Map.take(txu, [:tx_encoded, :hash, :signature])
      VanillaSer.encode(txu)
    end

    def unpack(tx_packed) do
      txu = VanillaSer.decode!(tx_packed)
      tx = VanillaSer.decode!(Map.fetch!(txu, "tx_encoded"))
      txu = Map.put(txu, "tx", tx)
      normalize_atoms(txu)
    end

   def test() do
      pk = Application.fetch_env!(:ama, :trainer_pk)
      tx = %{
         signer: pk,
         nonce: :os.system_time(:nanosecond),
         actions: [%{op: "call", contract: "Epoch", function: "fake", args: []}]
      }
      tx_encoded = VanillaSer.encode(tx)
      tx_packed = VanillaSer.encode(%{tx_encoded: tx_encoded})

      sk = Application.fetch_env!(:ama, :trainer_sk)
      tx_packed = TX.build(sk, "Epoch", "submit_sol", [:crypto.strong_rand_bytes(256)])
   end
end
