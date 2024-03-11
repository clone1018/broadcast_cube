defmodule BroadcastCube.Application do
  use Application

  require Logger

  @ip {127, 0, 0, 1}
  @port 8829

  @impl true
  def start(_type, _args) do
    Logger.configure(level: :info)

    children = [
      {Bandit, plug: BroadcastCube.Router, ip: @ip, port: @port},
      {BroadcastCube.WHIPSupervisor, []},
      {Registry, [keys: :unique, name: :whip_registry]},
      {BroadcastCube.WHEPSupervisor, []},
      {Registry, [keys: :unique, name: :whep_registry]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
