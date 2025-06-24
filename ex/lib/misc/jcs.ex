defmodule JCS do
    def serialize(map) when is_map(map) do
        map
        |> serialize_1()
        |> JSX.encode!()
    end
    defp serialize_1(map) do
        serialize_list = fn(list, self)->
            Enum.map(list, fn(v)->
                cond do
                    is_map(v)-> serialize_1(v)
                    is_list(v)-> self.(v)
                    true -> v
                end
            end)
        end
        Enum.map(map, fn{k,v}->
            cond do
                is_map(v) -> {k, serialize_1(v)}
                is_list(v) -> {k, serialize_list.(v, serialize_list)}
                true -> {k,v}
            end
        end)
        |> Enum.sort_by(& &1)
        |> case do
            [] -> %{}
            list -> list
        end
    end

    def validate(binary) do
        map = JSX.decode!(binary, labels: :attempt_atom)
        map
        |> serialize()
        |> Kernel.==(binary)
        |> case do
            true -> map
            false -> nil
        end
    end
end
