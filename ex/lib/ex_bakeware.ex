defmodule Ama.Bakeware do
    use Bakeware.Script
    require Logger

    @impl Bakeware.Script
    def main(args) do
        Ama.start(nil, [])
        receive do end
        0
    end
end
