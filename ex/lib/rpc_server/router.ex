defmodule Ama.RpcServer do
  use Plug.Router

  plug :match
  plug :dispatch

  post "/" do
    {:ok, body, _conn} = Plug.Conn.read_body(conn)

    case Jason.decode(body) do
      {:ok, %{"method" => method} = params} ->
        result = call_dynamic_method(method, params)

        # Konvertiere das Ergebnis in ein JSON-kompatibles Format
        json_result =
          case result do
            {:ok, value} -> %{status: "success", result: value}
            {:error, reason} -> %{status: "error", error: reason}
            _ -> %{status: "unknown", result: result}
          end

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(json_result))

      {:error, _reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "Invalid JSON"}))
    end
  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end

  defp call_dynamic_method(method, params) do
    case String.split(method, "_", parts: 2) do
      [module_name, function_name] ->
        module = String.to_existing_atom("Elixir." <> module_name)
        function = String.to_existing_atom(function_name)

        # Prüfe die Arity (Argumentanzahl) der Funktion dynamisch
        cond do
          :erlang.function_exported(module, function, 1) ->
            {:ok, apply(module, function, [params])} # Mit einem Argument aufrufen

          :erlang.function_exported(module, function, 0) ->
            {:ok, apply(module, function, [])} # Ohne Argumente aufrufen

          true ->
            {:error, "Function #{function_name}/0 or #{function_name}/1 not found in #{module_name}"}
        end

      _ ->
        {:error, "Invalid method format"}
    end
  rescue
    error in [UndefinedFunctionError, ArgumentError] ->
      {:error, "Method not found or invalid: #{inspect(error)}"}
  end
end

