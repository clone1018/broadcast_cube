defmodule BroadcastCube.WHIPConnection do
  use GenServer
  require Logger

  alias ExWebRTC.{PeerConnection, SessionDescription, MediaStreamTrack}

  def start_link(stream_key) do
    GenServer.start_link(__MODULE__, stream_key, name: via_tuple(stream_key))
  end

  def start_stream(stream_key, offer) do
    stream_key |> via_tuple() |> GenServer.call({:start_stream, offer})
  end

  def get_tracks(stream_key) do
    stream_key |> via_tuple() |> GenServer.call(:get_tracks)
  end

  def add_viewer(stream_key, viewer_pid) do
    stream_key |> via_tuple() |> GenServer.cast({:add_viewer, viewer_pid})
  end

  def child_spec(stream_key) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [stream_key]},
      restart: :temporary
    }
  end

  def stop_stream(stream_key, stop_reason \\ :normal) do
    # Given the :transient option in the child spec, the GenServer will restart
    # if any reason other than `:normal` is given.
    Logger.info("Stopping stream for #{stream_key}")
    stream_key |> via_tuple() |> GenServer.stop(stop_reason)
  end

  @impl true
  def init(stream_key) do
    Logger.info("Starting stream for #{stream_key}")

    {:ok, pc} =
      PeerConnection.start_link(
        ice_servers: [
          # %{urls: "stun:stun.l.google.com:19302"}
        ]
      )

    state = %{
      peer_connection: pc,
      video_track_id: nil,
      audio_track_id: nil,
      video_track: nil,
      audio_track: nil,
      viewers: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:start_stream, offer}, _from, state) do
    Logger.info("Received SDP offer: \n#{offer}")

    offer = String.replace(offer, "OPUS", "opus")

    :ok =
      PeerConnection.set_remote_description(state.peer_connection, %SessionDescription{
        type: :offer,
        sdp: offer
      })

    {:ok, answer_without_candidates} = PeerConnection.create_answer(state.peer_connection)

    :ok = PeerConnection.set_local_description(state.peer_connection, answer_without_candidates)
    answer = PeerConnection.get_current_local_description(state.peer_connection)

    Logger.info("Sent SDP answer: \n#{answer.sdp}")

    {:reply, {:ok, answer.sdp}, state}
  end

  def handle_call(:get_tracks, _from, state) do
    {:reply, {:ok, audio: state.audio_track, video: state.video_track}, state}
  end

  @impl true
  def handle_cast({:add_viewer, viewer_pid}, state) do
    {:noreply, %{state | viewers: [viewer_pid | state.viewers]}}
  end

  @impl true
  def handle_info({:ex_webrtc, _from, msg}, state) do
    handle_webrtc_msg(msg, state)
  end

  defp handle_webrtc_msg({:track, %MediaStreamTrack{kind: :video, id: id} = track}, state) do
    Logger.info("handle_webrtc_msg {:track, %MediaStreamTrack{kind: :video, id: #{id}}}")

    {:noreply,
     %{
       state
       | video_track_id: id,
         video_track: track
     }}
  end

  defp handle_webrtc_msg({:track, %MediaStreamTrack{kind: :audio, id: id} = track}, state) do
    Logger.info("handle_webrtc_msg {:track, %MediaStreamTrack{kind: :audio, id: #{id}}}")

    {:noreply,
     %{
       state
       | audio_track_id: id,
         audio_track: track
     }}
  end

  defp handle_webrtc_msg({:rtp, _id, %{payload: <<>>}}, state) do
    Logger.info("handle_webrtc_msg {:rtp, _id, %{payload: <<>>}}")
    # we're ignoring packets with padding only, as these are most likely used
    # for network bandwidth probing
    {:noreply, state}
  end

  defp handle_webrtc_msg({:rtp, id, %ExRTP.Packet{} = packet}, %{video_track_id: id} = state) do
    for viewer <- state.viewers do
      send(viewer, {:video_rtp, packet})
    end

    {:noreply, state}
  end

  defp handle_webrtc_msg({:rtp, id, packet}, %{audio_track_id: id} = state) do
    for viewer <- state.viewers do
      send(viewer, {:audio_rtp, packet})
    end

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
    do: {:via, Registry, {:whip_registry, name}}
end
