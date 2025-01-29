import Config

config :logger, truncate: :infinity

config :ama, :version, Mix.Project.config[:version]

config :ama, :entry_size, 1432
config :ama, :tx_size, 768
config :ama, :attestation_size, 512
config :ama, :quorum, 3

config :ama, :rpc_port, 4000

