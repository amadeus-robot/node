defmodule Ama.RpcServer do
  use Plug.Router
  plug :fetch_auth
  plug :match
  plug :dispatch


  defp fetch_auth(conn, _opts) do
    username = Application.get_env(:ama, :rpc_user) || ""
    password = Application.get_env(:ama, :rpc_password) || ""
  
    case get_req_header(conn, "authorization") do
      ["Basic " <> _] ->
        Plug.BasicAuth.basic_auth(conn, username: username, password: password)
      _ ->
        # No authentication header, assume empty username and password
        auth_header = "Basic " <> Base.encode64(":")
        conn
        |> put_req_header("authorization", auth_header)
        |> Plug.BasicAuth.basic_auth(username: username, password: password)
    end
  end
  post "/" do
    {:ok, body, _conn} = Plug.Conn.read_body(conn)

    case Jason.decode(body) do
      {:ok, %{"method" => method} = params} ->
        result = call_dynamic_method(method, params)

        # Format the result here
        formatted_result = case result do
          {:ok, value} -> %{status: "success", result: value}
          {:error, reason} -> %{status: "error", error: reason}
          {:start, data} -> %{status: "start", data: data}
          {:stop} -> %{status: "success", result: "stopped"}
          value when is_map(value) or is_list(value) -> %{status: "success", result: value}
          value -> %{status: "success", result: value}
        end

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(formatted_result))

      {:error, _reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{status: "error", error: "Invalid JSON"}))
    end

  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end
  defp call_dynamic_method(method, params) do
    # Split the method name into module and function parts
    case String.split(method, "_", parts: 2) do
      [module_name, function_name] ->
        # Convert module and function names to atoms dynamically
        module = String.to_existing_atom("Elixir." <> module_name)
        function = String.to_existing_atom(function_name)

        # Dynamically check function arity and execute
        result = cond do
          # Check if function with 1 argument exists
          :erlang.function_exported(module, function, 1) ->
            apply(module, function, [params])

          # Check if function with 0 arguments exists
          :erlang.function_exported(module, function, 0) ->
            apply(module, function, [])

          # If no matching function is found, return an error
          true ->
            {:error, "Function #{function_name}/0 or #{function_name}/1 not found in #{module_name}"}
        end

        # Return the result directly without additional formatting
        result

      # Handle invalid method format
      _ ->
        {:error, "Invalid method format"}
    end
  rescue
    # Handle exceptions during method invocation
    error in [UndefinedFunctionError, ArgumentError] ->
      {:error, "Method not found or invalid: #{inspect(error)}"}
  end

end

