defmodule Bonfire.Geolocate.Places do

  def fetch_places(socket) do
    with {:ok, places} <-
           Bonfire.Geolocate.GraphQL.geolocations(%{limit: 15}, %{
             context: %{current_user: Map.get(socket.assigns, :current_user)}
           }) do
      # [
      #   %{id: 1, lat: 51.5, long: -0.09, selected: false},
      #   %{id: 2, lat: 51.5, long: -0.099, selected: true}
      # ]

      places.edges
    else
      _e ->
        nil
    end
  end


  def fetch_place_things(filters, socket) do
    with {:ok, things} <-
           ValueFlows.Planning.Intent.Intents.many(filters) do
      IO.inspect(things)

      things =
        things
        |> Enum.map(
          &Map.merge(
            Bonfire.Geolocate.Geolocations.populate_coordinates(Map.get(&1, :at_location)),
            &1 || %{}
          )
        )

      IO.inspect(things)

      things
    else
      _e ->
        fetch_places(socket)
    end
  end

  def fetch_place(id, socket) do
    with {:ok, place} <-
           Bonfire.Geolocate.GraphQL.geolocation(%{id: id}, %{
             context: %{current_user: socket.assigns.current_user}
           }) do
      place
    else
      _e ->
        nil
    end
  end

end
