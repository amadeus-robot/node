defmodule Util do
    def sbash(term) do
        term = "#{term}"
        term = String.replace(term, "'", "")
        if term == "" do "" else "'#{term}'" end
    end

    def alphanumeric(string) do
        string
        |> String.to_charlist()
        |> Enum.filter(fn(char)->
            char in 97..122
            || char in 65..90
            || char in 48..57
        end)
        |> List.to_string()
    end

    def ascii(string) do
        string
        |> String.to_charlist()
        |> Enum.filter(fn(char)->
            char in 97..122
            || char in 65..90
            || char in 48..57
            || char in [95, 45] #"_-"
        end)
        |> List.to_string()
    end

    def alphanumeric_hostname(string) do
        string
        |> String.to_charlist()
        |> Enum.filter(fn(char)->
            char in 97..122
            || char in 48..57
            || char in [45] #"-"
        end)
        |> List.to_string()
    end

    def sext(path) do
        ext = Path.extname(path)
        |> ascii()
        "." <> ext
    end

    def url(url) do
        String.trim(url, "/")
    end

    def url(url, path) do
        String.trim(url, "/") <> path
    end

    def url_to_ws(url, path) do
        url = String.trim(url, "/") <> path
        url = String.replace(url, "https://", "wss://")
        url = String.replace(url, "http://", "ws://")
    end

    def get(url, headers \\ %{}, opts \\ %{}) do
        %{host: host} = URI.parse(url)
        ssl_opts = [
            {:server_name_indication, '#{host}'},
            {:verify,:verify_peer},
            {:depth,99},
            {:cacerts, :certifi.cacerts()},
            #{:verify_fun, verifyFun},
            {:partial_chain, &Photon.GenTCP.partial_chain/1},
            {:customize_hostname_check, [{:match_fun, :public_key.pkix_verify_hostname_match_fun(:https)}]}
        ]
        opts = Map.merge(opts, %{ssl_options: ssl_opts})
        :comsat_http.get(url, headers, opts)
    end

    def get_json(url, headers \\ %{}, opts \\ %{}) do
        {labels, opts} = Map.pop(opts, :labels, :attempt_atom)
        {:ok, %{body: body}} = get(url, headers, opts)
        #IO.inspect body
        JSX.decode!(body, [{:labels, labels}])
    end

    def delete(url, body, headers \\ %{}, opts \\ %{}) do
        %{host: host} = URI.parse(url)
        ssl_opts = [
            {:server_name_indication, '#{host}'},
            {:verify,:verify_peer},
            {:depth,99},
            {:cacerts, :certifi.cacerts()},
            #{:verify_fun, verifyFun},
            {:partial_chain, &Photon.GenTCP.partial_chain/1},
            {:customize_hostname_check, [{:match_fun, :public_key.pkix_verify_hostname_match_fun(:https)}]}
        ]
        opts = Map.merge(opts, %{ssl_options: ssl_opts})
        body = if !is_binary(body) do JSX.encode!(body) else body end
        :comsat_http.delete(url, headers, body, opts)
    end

    def delete_json(url, body, headers \\ %{}, opts \\ %{}) do
        {labels, opts} = Map.pop(opts, :labels, :attempt_atom)
        {:ok, %{body: body}} = delete(url, body, headers, opts)
        JSX.decode!(body, [{:labels, labels}])
    end

    def post(url, body, headers \\ %{}, opts \\ %{}) do
        %{host: host} = URI.parse(url)
        ssl_opts = [
            {:server_name_indication, '#{host}'},
            {:verify,:verify_peer},
            {:depth,99},
            {:cacerts, :certifi.cacerts()},
            #{:verify_fun, verifyFun},
            {:partial_chain, &Photon.GenTCP.partial_chain/1},
            {:customize_hostname_check, [{:match_fun, :public_key.pkix_verify_hostname_match_fun(:https)}]}
        ]
        opts = Map.merge(opts, %{ssl_options: ssl_opts})
        body = if !is_binary(body) do JSX.encode!(body) else body end
        :comsat_http.post(url, headers, body, opts)
    end

    def post_json(url, body, headers \\ %{}, opts \\ %{}) do
        {labels, opts} = Map.pop(opts, :labels, :attempt_atom)
        {:ok, %{body: body}} = post(url, body, headers, opts)
        #IO.inspect body
        JSX.decode!(body, [{:labels, labels}])
    end

    def put(url, body, headers \\ %{}, opts \\ %{}) do
        %{host: host} = URI.parse(url)
        ssl_opts = [
            {:server_name_indication, '#{host}'},
            {:verify,:verify_peer},
            {:depth,99},
            {:cacerts, :certifi.cacerts()},
            #{:verify_fun, verifyFun},
            {:partial_chain, &Photon.GenTCP.partial_chain/1},
            {:customize_hostname_check, [{:match_fun, :public_key.pkix_verify_hostname_match_fun(:https)}]}
        ]
        opts = Map.merge(opts, %{ssl_options: ssl_opts})
        body = if !is_binary(body) do JSX.encode!(body) else body end
        :comsat_http.put(url, headers, body, opts)
    end

    def put_json(url, body, headers \\ %{}, opts \\ %{}) do
        {labels, opts} = Map.pop(opts, :labels, :attempt_atom)
        {:ok, %{body: body}} = put(url, body, headers, opts)
        JSX.decode!(body, [{:labels, labels}])
    end

    def b3sum(path) do
        {b3sum, 0} = System.shell("b3sum --no-names --raw #{U.b(path)}")
        Base.hex_encode32(b3sum, padding: false, case: :lower)
    end
end