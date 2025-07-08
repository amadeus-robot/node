defmodule SolBloom do
    @n 1_000_000
    @k 2

    @pages 256
    @page_size 65_536 #8kb
    @m (@pages * @page_size) #16_777_216 #2MB

    def pages(), do: @pages
    def page_size(), do: @page_size
    def m(), do: @m

    #n element, m bits, k hashes  Bloom.simulate_fpr 10_000_000, 64_000_000, 8
    def simulate_fpr(n, m, k) when n > 0 and m > 0 and k > 0 do
      :math.pow(1.0 - :math.exp(-k * n / m), k)
    end

    def hash(bin) do
      digest = Blake3.hash(bin)
      for <<word::little-128 <- digest>>, reduce: [] do
        acc -> [rem(word, @m) | acc]
      end
    end

    def segs(digest) do
      idxs = for <<word::little-128 <- digest>>, reduce: [] do
        acc -> [rem(word, @m) | acc]
      end
      Enum.map(idxs, fn(idx)->
        %{page: div(idx, @page_size),  bit_offset: rem(idx, @page_size)}
      end)
    end
end
