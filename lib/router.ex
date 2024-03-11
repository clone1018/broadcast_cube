defmodule BroadcastCube.Router do
  use Plug.Router

  require Logger

  alias BroadcastCube.{
    WHEPConnection,
    WHIPSupervisor,
    WHIPConnection,
    WHEPSupervisor
  }

  use Plug.Debugger
  use Plug.ErrorHandler

  plug(Plug.Logger, log: :info)
  plug(Plug.Static, at: "/", from: "assets")
  plug(:match)
  plug(:dispatch)

  # WebRTC-HTTP Egress Protocol
  # Eg: Browser Viewer => BroadcastCube
  options "/api/whep" do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> send_resp(200, "")
  end

  post "/api/whep/:stream_key" do
    with {:ok, offer, _} <- read_body(conn),
         viewer_id <- unique_viewer_id(),
         {:ok, _viewer_pid} <- WHEPSupervisor.start_child(viewer_id),
         {:ok, answer} <- WHEPConnection.watch_stream(viewer_id, stream_key, offer) do
      conn
      |> put_resp_content_type("application/sdp")
      |> put_resp_header("access-control-expose-headers", "location")
      |> put_resp_header("access-control-allow-origin", "*")
      |> put_resp_header("location", "/api/resource/#{viewer_id}")
      |> send_resp(201, answer)
    end
  end

  patch "/api/resource/:viewer_id" do
    # Ice candidates trickle
    send_resp(conn, 204, "ok")
  end

  delete "/api/resource/:viewer_id" do
    :ok = WHEPConnection.stop_stream(viewer_id)

    send_resp(conn, 200, "ok")
  end

  # WebRTC-HTTP Ingestion Protocol
  # Eg: OBS => BroadcastCube
  post "/api/whip" do
    conn = conn |> put_resp_header("access-control-allow-origin", "*")

    with ["Bearer " <> stream_key] <- get_req_header(conn, "authorization"),
         {:ok, offer, _} <- read_body(conn),
         {:ok, _stream_pid} <- WHIPSupervisor.start_child(stream_key),
         {:ok, answer} <- WHIPConnection.start_stream(stream_key, offer) do
      conn
      |> put_resp_content_type("application/sdp")
      |> put_resp_header("Access-Control-Expose-Headers", "expire")
      |> put_resp_header("location", "/api/whip")
      |> send_resp(201, answer)
    else
      [] -> send_error(conn, "Authorization header was not set")
      {:error, error} -> send_error(conn, "Failed to read HTTP body due to #{inspect(error)}")
      error -> send_error(conn, "Unexpected error negotiating stream #{inspect(error)}")
    end
  end

  delete "/api/whip" do
    with ["Bearer " <> stream_key] <- get_req_header(conn, "authorization"),
         :ok <- WHIPConnection.stop_stream(stream_key) do
      send_resp(conn, 200, "ok")
    else
      [] -> send_error(conn, "Stream is not currently live")
      _ -> send_error(conn, "Unexpected error stopping stream")
    end
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  defp send_error(conn, message, code \\ 400) do
    Logger.error(message)
    send_resp(conn, code, message)
  end

  defp unique_viewer_id,
    do: for(_ <- 1..10, into: "", do: <<Enum.random(~c"0123456789abcdef")>>)
end
