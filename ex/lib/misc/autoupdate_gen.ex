defmodule AutoUpdateGen do
  use GenServer

  def start_link() do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    :erlang.send_after(30_000, self(), :tick)
    {:ok, state}
  end

  def handle_info(:tick, state) do
    state = if true do tick(state) else state end
    :erlang.send_after(30_000, self(), :tick)
    {:noreply, state}
  end

  def tick(state) do
    upgrade()
    state
  end

  def upgrade() do
    url = "https://api.github.com/repos/amadeus-robot/node/releases/latest"
    {:ok, %{status_code: 200, body: body}} = :comsat_http.get(url, %{}, %{:ssl_options=> [{:server_name_indication, 'api.github.com'}, {:verify, :verify_none}]})
    json = JSX.decode!(body, labels: :atom)
    if Application.fetch_env!(:ama, :version) != String.trim(json.tag_name, "v") do
        download_url = Enum.find_value(json.assets, fn(asset)->
            asset.name == "amadeusd" and asset.browser_download_url
        end)
        if download_url do
            IO.inspect {:downloading_upgrade, download_url}
            {:ok, %{status_code: 200, body: bin}} = :comsat_http.get(download_url, %{}, %{:ssl_options=> [{:server_name_indication, 'github.com'}, {:verify, :verify_none}]})

            cwd_dir = File.cwd!()
            path_tmp = Path.join(cwd_dir, "amadeusd_tmp")
            File.write!(path_tmp, bin)
            File.rename!(path_tmp, Path.join(cwd_dir, "amadeusd"))
            :erlang.halt()
        end
    end
  end
end