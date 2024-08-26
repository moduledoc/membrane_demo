defmodule Membrane.Demo.RTSPToHLS.Pipeline do
  @moduledoc """
  The pipeline, which converts the RTP stream to HLS.
  """
  use Membrane.Pipeline

  require Logger

  @impl true
  def handle_init(_context, options) do
    Logger.debug("Source handle_init options: #{inspect(options)}")

    spec = [
      child(:source, %Membrane.RTSP.Source{
        transport: {:udp, options.port, options.port + 5},
        allowed_media_types: [:video],
        stream_uri: options.stream_url,
        on_connection_closed: :send_eos
      }),
      child(
        :hls,
        %Membrane.HTTPAdaptiveStream.SinkBin{
          target_window_duration: Membrane.Time.seconds(120),
          manifest_module: Membrane.HTTPAdaptiveStream.HLS,
          storage: %Membrane.HTTPAdaptiveStream.Storages.FileStorage{
            directory: options.output_path
          }
        }
      )
    ]

    {[spec: spec],
     %{
       video: nil,
       output_path: options.output_path,
       parent_pid: options.parent_pid
     }}
  end

  @impl true
  def handle_child_notification({:new_tracks, tracks}, :source, _ctx, state) do
    Logger.debug(":new_rtp_stream")

    {spec, rtp_playing} =
      Enum.map_reduce(tracks, false, fn {ssrc, track}, rtp_playing ->
        create_spec_for_track(ssrc, track, rtp_playing)
      end)

    if not rtp_playing, do: raise("No video tracks received")

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification({:track_playable, _ref}, :hls, _ctx, state) do
    send(state.parent_pid, :track_playable)
    {[], state}
  end

  @impl true
  def handle_child_notification(notification, element, _ctx, state) do
    Logger.warning("Unknown notification: #{inspect(notification)}, el: #{inspect(element)}")

    {[], state}
  end

  @spec create_spec_for_track(pos_integer(), map(), boolean()) ::
          {Membrane.ChildrenSpec.t(), boolean()}
  defp create_spec_for_track(ssrc, %{type: :video} = track, false) do
    {spss, ppss} =
      case track.fmtp.sprop_parameter_sets do
        nil -> {[], []}
        parameter_sets -> {parameter_sets.sps, parameter_sets.pps}
      end

    spec =
      get_child(:source)
      |> via_out(Pad.ref(:output, ssrc))
      |> child(
        :video_nal_parser,
        %Membrane.H264.Parser{
          spss: spss,
          ppss: ppss,
          generate_best_effort_timestamps: %{framerate: {30, 1}}
        }
      )
      |> via_in(:input,
        options: [encoding: :H264, segment_duration: Membrane.Time.seconds(4)]
      )
      |> get_child(:hls)

    {spec, true}
  end

  defp create_spec_for_track(ssrc, _track, rtp_playing) do
    Logger.warning("new_rtp_stream Unsupported stream connected")

    spec =
      get_child(:rtp)
      |> via_out(Pad.ref(:output, ssrc))
      |> child({:fake_sink, ssrc}, Membrane.Element.Fake.Sink.Buffers)

    {spec, rtp_playing}
  end
end
