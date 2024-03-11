defmodule BroadcastCube.WHEPConnection do
  use GenServer

  require Logger

  alias ExWebRTC.{
    PeerConnection,
    SessionDescription,
    MediaStreamTrack
  }

  def start_link(viewer_id) do
    GenServer.start_link(__MODULE__, viewer_id, name: via_tuple(viewer_id))
  end

  def child_spec(viewer_id) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [viewer_id]},
      restart: :temporary
    }
  end

  def watch_stream(viewer_id, stream_key, offer) do
    viewer_id |> via_tuple() |> GenServer.call({:whep, stream_key, offer})
  end

  def stop_stream(viewer_id, stop_reason \\ :normal) do
    # Given the :transient option in the child spec, the GenServer will restart
    # if any reason other than `:normal` is given.
    Logger.info("Stopping stream for #{viewer_id}")
    viewer_id |> via_tuple() |> GenServer.stop(stop_reason)
  end

  @impl true
  def init(_) do
    {:ok, pc} =
      PeerConnection.start_link(
        ice_servers: [
          # %{urls: "stun:stun.l.google.com:19302"}
        ],
        video_codecs: [
          %ExWebRTC.RTPCodecParameters{
            payload_type: 97,
            mime_type: "video/H264",
            clock_rate: 90_000
          }
        ]
      )

    video_track = MediaStreamTrack.new(:video)
    audio_track = MediaStreamTrack.new(:audio)

    {:ok, _sender} = PeerConnection.add_track(pc, video_track)
    {:ok, _sender} = PeerConnection.add_track(pc, audio_track)

    Logger.info("Created new WHEPConnection")

    state = %{
      peer_connection: pc,
      ice_candidates: [],
      audio_sender: nil,
      video_sender: nil,
      audio_track_id: audio_track.id,
      video_track_id: video_track.id,
      stream_key: nil,
      video_timestamp: 50000,
      video_seq_no: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:stop}, _from, state) do
    {:stop, "client stopped viewing", :foo, state}
  end

  def handle_call({:whep, stream_key, data}, _from, state) do
    Logger.info("Received SDP offer: \n#{data}")

    :ok =
      PeerConnection.set_remote_description(state.peer_connection, %SessionDescription{
        type: :offer,
        sdp: data
      })

    {:ok, answer_without_candidates} = PeerConnection.create_answer(state.peer_connection)

    :ok = PeerConnection.set_local_description(state.peer_connection, answer_without_candidates)

    answer = PeerConnection.get_current_local_description(state.peer_connection)

    Logger.info("Sent SDP answer: \n#{answer.sdp}")

    {:reply, {:ok, answer.sdp}, %{state | stream_key: stream_key}}
  end

  @impl true
  def handle_info({:ex_webrtc, _from, msg} = raw, state) do
    Logger.debug("Got: #{inspect(raw)}")
    handle_webrtc_msg(msg, state)
  end

  def handle_info({:video_rtp, %ExRTP.Packet{} = packet}, state) do
    PeerConnection.send_rtp(state.peer_connection, state.video_track_id, packet)
    {:noreply, state}
  end

  def handle_info({:audio_rtp, packet}, state) do
    PeerConnection.send_rtp(state.peer_connection, state.audio_track_id, packet)
    {:noreply, state}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.warning("WHEPConnection connection was terminated, reason: #{inspect(reason)}")
  end

  defp handle_webrtc_msg({:connection_state_change, :connected}, state) do
    BroadcastCube.WHIPConnection.add_viewer(state.stream_key, self())

    {:noreply, state}
  end

  defp handle_webrtc_msg({:rtcp, _}, state) do
    {:noreply, state}
  end

  defp handle_webrtc_msg(msg, state) do
    Logger.warning("Unhandled: #{inspect(msg)}")

    {:noreply, state}
  end

  # Private
  defp via_tuple(name),
    do: {:via, Registry, {:whep_registry, name}}
end
