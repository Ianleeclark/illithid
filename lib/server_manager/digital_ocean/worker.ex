defmodule Illithid.ServerManager.DigitalOcean.Worker do
  @moduledoc false
  @behaviour Illithid.ServerManager.WorkerBehaviour

  use GenServer, restart: :transient

  @api Application.get_env(:illithid, :digital_ocean)[:api_module]

  alias Illithid.ServerManager.Models.{Region, Server, ServerCreationContext}

  require Logger

  #######################
  # GenServer Callbacks #
  #######################

  def start_link([], {_, _} = args) do
    start_link(args)
  end

  def start_link({%ServerCreationContext{server_id: server_id, image: image}, region}) do
    with {:ok, servers} <- @api.list_servers(),
         {:ok, images} <- @api.list_images(true) do
      server = Enum.find(servers, fn server -> server.name == server_id end)

      if server != nil do
        # TODO(ian): Determine if server is already running. If so, log it and create this genserver with that in the Server
      else
        image_id =
          images
          |> Map.get("images")
          |> Enum.find(fn
            %{"name" => ^image} -> true
            _ -> false
          end)
          |> Map.get("id")

        create_server(server_id, region, image_id)
      end
    end
  end

  def init([server, name]) do
    Process.flag(:trap_exit, true)
    {:ok, %{server: server, name: name}}
  end

  ####################
  # Client Functions #
  ####################

  @spec server_alive?(pid) :: boolean
  def server_alive?(pid) when is_pid(pid) do
    GenServer.call(pid, :server_alive?)
  end

  @spec destroy_server(pid()) :: {:ok, Server.t()} | {:error, String.t()}
  def destroy_server(pid) when is_pid(pid) do
    GenServer.call(pid, :destroy)
  end

  @spec get_server_from_process(pid) :: Server.t()
  def get_server_from_process(pid) do
    GenServer.call(pid, :get_server)
  end

  @spec get_server_name(pid) :: String.t()
  def get_server_name(pid) do
    GenServer.call(pid, :name)
  end

  ################
  # Handle Calls #
  ################

  def handle_call(:server_alive?, _from, state) do
    {:reply, @api.server_alive?(state.server), state}
  end

  def handle_call(:destroy, _from, state) do
    case @api.destroy_server(state.server) do
      {:ok, _} -> {:stop, :normal, :ok, state}
      _ -> {:reply, {:error, "Failed to stop server."}}
    end
  rescue
    _ ->
      {:stop, :normal, :ok, state}
  end

  def handle_call(:get_server, _from, state) do
    {:reply, state.server, state}
  end

  def handle_call(:name, _from, state) do
    {:reply, state.name, state}
  end

  def handle_call(:check_server_status, _from, state) do
    updated_server = check_server_status(state.server)
    {:reply, state.server, Map.put(state, :server, updated_server)}
  end

  def handle_info(:check_server_status, state) do
    updated_server = check_server_status(state.server)
    {:noreply, Map.put(state, :server, updated_server)}
  end

  def handle_info(:shutdown, state) do
    {:stop, :normal, state}
  end

  ##############
  # Misc Calls #
  ##############

  @spec create_server(String.t(), Region.t(), image :: String.t()) ::
          {:ok, Server.t()} | {:error, String.t()}
  defp create_server(server_name, %Region{slug: region_slug}, image) do
    # TODO(ian): Don't convert this to an atom, is pretty dumb
    name_atom = String.to_atom(server_name)

    # TODO(ian): This should re-use the ServerContext mentioned somewhere above
    new_server_request = %{
      "name" => server_name,
      "region" => region_slug,
      "size" => "s-1vcpu-1gb",
      "image" => image
    }

    Logger.info("Creating new server with name #{server_name}")

    with {:ok, %Server{} = server} <- @api.create_server(new_server_request) do
      GenServer.start_link(
        __MODULE__,
        [server, server_name],
        name: name_atom
      )
    else
      {:error, _reason} = retval -> retval
    end
  end

  ###########################
  # Server State Management #
  ###########################

  @spec check_server_status(Server.t()) :: any()
  def check_server_status(%Server{id: server_id}) do
    case @api.get_server(server_id) do
      {:ok, %Server{} = server} ->
        server

      _ ->
        {:error, :check_server_status_failed}
    end
  end

  #################################################
  # @spec server_spawned?(number) :: boolean      #
  # defp server_spawned?(server_id) do            #
  #   case @api.get_server(server_id) do          #
  #     {:ok, %Server{status: :active}} -> #
  #       true                                    #
  #                                               #
  #     _ ->                                      #
  #       false                                   #
  #   end                                         #
  # end                                           #
  #################################################
end
