defmodule NodeProto do
  def ping() do
    tip = Consensus.chain_tip_entry()
    temporal = tip |> Map.take([:header, :signature, :mask])
    rooted = Fabric.rooted_tip_entry() |> Map.take([:header, :signature, :mask])
    %{op: :ping, temporal: temporal, rooted: rooted, ts_m: :os.system_time(1000)}
  end

  def pong(ts_m) do
    %{op: :pong, ts_m: ts_m}
  end

  def who_are_you() do
    %{op: :who_are_you}
  end

  def txpool(txs_packed) do
    %{op: :txpool, txs_packed: txs_packed}
  end

  def peers(ips) do
    %{op: :peers, ips: ips}
  end

  def sol(sol) do
    %{op: :sol, sol: sol}
  end

  def entry(map) do
    msg = %{op: :entry, entry_packed: map.entry_packed}
    msg = if !map[:attestation_packed] do msg else Map.put(msg, :attestation_packed, map.attestation_packed) end
    msg = if !map[:consensus_packed] do msg else Map.put(msg, :consensus_packed, map.consensus_packed) end
    msg
  end

  def attestation_bulk(attestations_packed) do
    %{op: :attestation_bulk, attestations_packed: attestations_packed}
  end

  def consensus_bulk(consensuses_packed) do
    %{op: :consensus_bulk, consensuses_packed: consensuses_packed}
  end

  def catchup_entry(heights) do
    %{op: :catchup_entry, heights: heights}
  end

  def catchup_tri(heights) do
    %{op: :catchup_tri, heights: heights}
  end

  def catchup_bi(heights) do
    %{op: :catchup_bi, heights: heights}
  end

  def catchup_attestation(hashes) do
    %{op: :catchup_attestation, hashes: hashes}
  end

  def special_business(business) do
    %{op: :special_business, business: business}
  end

  def special_business_reply(business) do
    %{op: :special_business_reply, business: business}
  end

  def solicit_entry(hash) do
    %{op: :solicit_entry, hash: hash}
  end

  def deflate_compress(data) do
    z = :zlib.open()
    :zlib.deflateInit(z, 6, :deflated, -15, 8, :default)
    compressed = :zlib.deflate(z, data, :finish)
    :zlib.deflateEnd(z)
    :zlib.close(z)
    :erlang.list_to_binary(compressed)
  end

  def deflate_decompress(compressed_data) do
    z = :zlib.open()
    :zlib.inflateInit(z, -15)
    decompressed = :zlib.inflate(z, compressed_data)
    :zlib.inflateEnd(z)
    :zlib.close(z)
    :erlang.list_to_binary(decompressed)
  end

  def compress(msg) do
    msg
    |> :erlang.term_to_binary([:deterministic])
    |> deflate_compress()
  end
  def encrypt_message_v2(msg_compressed, nil) do
    pk = Application.fetch_env!(:ama, :trainer_pk)
    sk = Application.fetch_env!(:ama, :trainer_sk)
    version_3byte = Application.fetch_env!(:ama, :version_3b)

    signature = BlsEx.sign!(sk, Blake3.hash(pk<>msg_compressed), BLS12AggSig.dst_node())

    ts_n = :os.system_time(:nanosecond)

    if byte_size(msg_compressed) < 1300 do
      [<<"AMA", version_3byte::binary, 0::7, 1::1, pk::binary, signature::binary, 0::16, 1::16, ts_n::64, byte_size(msg_compressed)::32, msg_compressed::binary>>]
    else
      shards = div(byte_size(msg_compressed)+1023, 1024)
      r = ReedSolomonEx.create_resource(shards, shards, 1024)
      ReedSolomonEx.encode_shards(r, msg_compressed)
      |> Enum.take(shards+1+div(shards,4))
      |> Enum.map(fn {idx, shard}->
        <<"AMA", version_3byte::binary, 0::7, 1::1, pk::binary, signature::binary, idx::16, (shards*2)::16, ts_n::64, byte_size(msg_compressed)::32, shard::binary>>
      end)
    end
  end
  def encrypt_message_v2(msg_compressed, shared_key) do
    pk = Application.fetch_env!(:ama, :trainer_pk)
    version_3byte = Application.fetch_env!(:ama, :version_3b)

    ts_n = :os.system_time(:nanosecond)
    iv = :crypto.strong_rand_bytes(12)
    key = :crypto.hash(:sha256, [shared_key, :binary.encode_unsigned(ts_n), iv])
    {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, msg_compressed, <<>>, 16, true)

    payload = <<iv::binary, tag::binary, ciphertext::binary>>
    if byte_size(payload) < 1380 do
      [<<"AMA", version_3byte::binary, 0, pk::binary, 0::16, 1::16, ts_n::64, byte_size(payload)::32, payload::binary>>]
    else
      shards = div(byte_size(payload)+1023, 1024)
      r = ReedSolomonEx.create_resource(shards, shards, 1024)
      ReedSolomonEx.encode_shards(r, payload)
      |> Enum.take(shards+1+div(shards,4))
      |> Enum.map(fn {idx, shard}->
        <<"AMA", version_3byte::binary, 0, pk::binary, idx::16, (shards*2)::16, ts_n::64, byte_size(payload)::32, shard::binary>>
      end)
    end
  end

  def unpack_message_v2(<<"AMA", version_3byte::3-binary, 0::7, 1::1, pk::48-binary, signature::96-binary,
    shard_index::16, shard_total::16, ts_n::64, original_size::32, msg_compressed_or_shard::binary>>) do
    try do
      if pk == Application.fetch_env!(:ama, :trainer_pk), do: throw(%{error: :msg_to_self})

      <<a,b,c>> = version_3byte
      version = "#{a}.#{b}.#{c}"

      %{error: :signature, pk: :binary.copy(pk), ts_nano: ts_n, shard_index: shard_index, shard_total: shard_total, version: version,
        signature: :binary.copy(signature), original_size: original_size, payload: msg_compressed_or_shard}
    catch
      throw,r -> %{error: r}
      e,r -> %{error: e, reason: r}
    end
  end

  def unpack_message_v2(<<"AMA", version_3byte::3-binary, 0::8, pk::48-binary,
    shard_index::16, shard_total::16, ts_n::64, original_size::32, msg_compressed_or_shard::binary>>) do
    try do
      if pk == Application.fetch_env!(:ama, :trainer_pk), do: throw(%{error: :msg_to_self})

      <<a,b,c>> = version_3byte
      version = "#{a}.#{b}.#{c}"

      %{error: :encrypted, pk: :binary.copy(pk), ts_nano: ts_n, shard_index: shard_index, shard_total: shard_total, version: version,
        original_size: original_size, payload: msg_compressed_or_shard}
    catch
      throw,r -> %{error: r}
      e,r -> %{error: e, reason: r}
    end
  end

  def unpack_message_v2(data) do
    unpack_message(data)
  end

  def pack_message(msg) do
    pk = Application.fetch_env!(:ama, :trainer_pk)
    sk = Application.fetch_env!(:ama, :trainer_sk)

    #TODO: enable later if needed
    #challenge = Application.fetch_env!(:ama, :challenge)
    #challenge_signature = Application.fetch_env!(:ama, :challenge_signature)
    #msg = Map.merge(msg, %{signer: pk, challenge: challenge, challenge_signature: challenge_signature})
    msg_packed = msg
    |> Map.put(:signer, pk)
    |> Map.put(:version, Application.fetch_env!(:ama, :version))
    |> :erlang.term_to_binary([:deterministic])
    hash = Blake3.hash(msg_packed)
    signature = BlsEx.sign!(sk, hash, BLS12AggSig.dst_node())
    msg_envelope = %{msg_packed: msg_packed, signature: signature}
    msg_envelope_packed = msg_envelope
    |> :erlang.term_to_binary([:deterministic])
    |> deflate_compress()

    iv = :crypto.strong_rand_bytes(12)
    {ciphertext, tag} = encrypt(iv, msg_envelope_packed)
    <<iv::12-binary, tag::16-binary, ciphertext::binary>>
  end

  def unpack_message(data) do
    try do
      <<iv::12-binary, tag::16-binary, ciphertext::binary>> = data
      plaintext = decrypt(iv, tag, ciphertext)
      msg_envelope = plaintext
      |> deflate_decompress()
      |> :erlang.binary_to_term([:safe])

      msg = :erlang.binary_to_term(msg_envelope.msg_packed, [:safe])
      hash = Blake3.hash(msg_envelope.msg_packed)
      if !BlsEx.verify?(msg.signer, msg_envelope.signature, hash, BLS12AggSig.dst_node()), do: throw(%{error: :invalid_signature})
      if msg.signer == Application.fetch_env!(:ama, :trainer_pk), do: throw(%{error: :msg_to_self})

      %{error: :old, msg: msg}
    catch
      throw,r -> %{error: r}
      e,r -> %{error: e, reason: r}
    end
  end

  #useless key to prevent udp noise
  def aes256key do
    <<0, 6, 2, 94, 44, 225, 200, 37, 227, 180, 114, 230, 230, 219, 177, 28,
    80, 19, 72, 13, 196, 129, 81, 216, 161, 36, 177, 212, 199, 6, 169, 26>>
  end

  def encrypt(iv, text) do
    {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, aes256key(), iv, text, <<>>, 16, true)
    {ciphertext, tag}
  end

  def decrypt(iv, tag, ciphertext) do
    :crypto.crypto_one_time_aead(:aes_256_gcm, aes256key(), iv, ciphertext, <<>>, tag, false)
  end
end
