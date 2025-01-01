defmodule UPOW do
	#1024 #262144
	def tensormath() do
		my_pk = Application.fetch_env!(:ama, :trainer_pk)
		tensormath(my_pk, my_pk)
	end

	def tensormath(trainer, computor) do
		epoch = Blockchain.epoch()
		nonce = :crypto.strong_rand_bytes(32)
		sol_seed = <<trainer::binary, computor::binary, epoch::32-little, nonce::binary>>
		sol_seed = sol_seed <> :binary.copy(<<0>>, 160 - byte_size(sol_seed))
		{calculate(sol_seed), sol_seed}
	end

	def calculate(sol_seed) do
		b = Blake3.new()
		Blake3.update(b, sol_seed)
		tensor = Enum.reduce(0..1023, %{}, fn(idx, acc)->
			acc = Map.put(acc, idx, Blake3.finalize_xof(b, 1024))
			Blake3.update(b, Blake3.finalize(b))
			acc
		end)
		random_walk_bin = Blake3.finalize_xof(b, 1024*8*2)
		walk_mul(random_walk_bin, tensor)
	end

	def walk_mul(<<>>, tensor) do
		b = Blake3.new()
		tensor = Enum.each(0..1023, fn(idx)->
			Blake3.update(b, tensor[idx])
		end)
		Blake3.finalize(b)
	end

	def walk_mul(<<index::16-little, rest::binary>>, tensor) do
		index = rem(index, 1024)
		{_row, new_row} = Enum.reduce(0..1023, {tensor[index], <<>>}, fn(idx, {row, new_row})->
		  element = :binary.at(row, idx)
			{row, <<new_row::binary, element*element>>}
		end)
		tensor = Map.put(tensor, index, new_row)
		walk_mul(rest, tensor)
	end

	def compute_for(trainer, computor, itrs \\ 30, difficulty \\ <<0,0xff>>)
	def compute_for(trainer, computor, 0, difficulty), do: nil
	def compute_for(trainer, computor, itrs, difficulty) do
		{hash, sol} = UPOW.tensormath(trainer, computor)
		if hash < difficulty do
			sol
		else
			compute_for(trainer, computor, itrs - 1, difficulty)
		end
	end

	def test() do
		Enum.reduce(1..10000, <<0xff>>, fn(itr, best)->
			IO.inspect {"pow #{itr} so far best sol", best}
			{hash, sol} = UPOW.tensormath()
			if hash < best do
				sol
			else
				best
			end
		end)
	end
end
