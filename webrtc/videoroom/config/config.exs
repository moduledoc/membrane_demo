import Config

config :membrane_videoroom_demo,
  ip: {0, 0, 0, 0},
  port: 8443,
  keyfile: "priv/certs/key.pem",
  certfile: "priv/certs/certificate.pem"

config :logger,
  level: :info,
  compile_time_purge_matching: [
    [level_lower_than: :info],
    # Silence warnings caused by in-band RTCP that we don't support yet
    [module: Membrane.SRTP.Decryptor, function: "handle_process/4", level_lower_than: :error],
    # Silence irrelevant warnings caused by resending handshake events
    [module: Membrane.SRTP.Encryptor, function: "handle_event/4", level_lower_than: :error]
  ]

config :logger, :console, metadata: [:room]