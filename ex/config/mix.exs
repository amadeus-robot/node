defmodule Ama.MixProject do
  use Mix.Project

  @app :ama

  def project do
    [
      app: @app,
      version: "0.1.2",
      elixir: "~> 1.17.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      build_embedded: Mix.env == :prod,
      releases: [{@app, release()}],
      preferred_cli_env: [release: :prod]
    ]
  end

  def application do
    apps = [
      extra_applications: [:iex, :logger, :crypto, :ssl, :inets]
    ]
    if Mix.env() == :prod do
      [{:mod, {Ama.Bakeware, []}} | apps]
    else
      [{:mod, {Ama, []}} | apps]
    end
  end

  defp deps do
    [
      {:bakeware, git: "https://github.com/bake-bake-bake/bakeware", branch: "main", runtime: false},

      {:photon, git: "https://github.com/vans163/photon.git"},
      {:mnesia_kv, git: "https://github.com/xenomorphtech/mnesia_kv.git"},

      {:blake3, git: "https://github.com/vans163/blake3", branch: "finalize_xof"},
      {:bls_ex, git: "https://github.com/amadeus-robot/bls_ex"},

      {:comsat, git: "https://github.com/vans163/ComSat.git"},


     # Plugins for RPC
      {:plug_cowboy, "~> 2.5"},
      {:jason, "~> 1.2"}
    

    ]
  end

  defp release do
    [
      overwrite: true,
      steps: [:assemble, &Bakeware.assemble/1],
      strip_beams: Mix.env() == :prod,
      bakeware: [
        compression_level: 1,
        #compression_level: 19,
        start_command: "start_iex"
      ],
    ]
  end
end
