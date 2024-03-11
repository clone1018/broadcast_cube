defmodule BroadcastCube.WHIPSupervisor do
  use DynamicSupervisor

  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def start_child(stream_key) do
    # Shorthand to retrieve the child specification from the `child_spec/1` method of the given module.
    child_specification = {BroadcastCube.WHIPConnection, stream_key}

    DynamicSupervisor.start_child(__MODULE__, child_specification)
  end

  @impl true
  def init(_arg) do
    # :one_for_one strategy: if a child process crashes, only that process is restarted.
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
