# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Geolocate.Geolocations do
  import Bonfire.Common.Config, only: [repo: 0]
  alias Bonfire.Common.Utils

  alias Bonfire.Geolocate.Geolocation
  alias Bonfire.Geolocate.Queries

  # alias CommonsPub.Characters
  # alias CommonsPub.Feeds.FeedActivities
  # alias CommonsPub.Workers.APPublishWorker
  # alias CommonsPub.Activities
  # alias CommonsPub.Feeds


  def cursor(:followers), do: &[&1.follower_count, &1.id]
  def test_cursor(:followers), do: &[&1["followerCount"], &1["id"]]

  @doc """
  Retrieves a single geolocation by arbitrary filters.
  Used by:
  * GraphQL Item queries
  * ActivityPub integration
  * Various parts of the codebase that need to query for geolocations (inc. tests)
  """
  def one(filters), do: repo().single(Queries.query(Geolocation, filters))

  @doc """
  Retrieves a list of geolocations by arbitrary filters.
  Used by:
  * Various parts of the codebase that need to query for geolocations (inc. tests)
  """
  def many(filters \\ []), do: {:ok, repo().all(Queries.query(Geolocation, filters))}

  ## mutations

  @spec create(any(), context :: any, attrs :: map) ::
          {:ok, Geolocation.t()} | {:error, Changeset.t()}
  def create(creator, %{} = context, attrs) when is_map(attrs) do
    repo().transact_with(fn ->
      with {:ok, attrs} <- resolve_mappable_address(attrs),
           {:ok, item} <- insert_geolocation(creator, context, attrs),
           {:ok, character} <- {:ok, nil} #Characters.create(creator, attrs, item), # FIXME
          #  act_attrs = %{verb: "created", is_local: true},
          #  {:ok, activity} <- Activities.create(creator, item, act_attrs),
          #  :ok <- publish(creator, context, item, activity, :created)
           do
        {:ok, populate_result(item, character)}
      end
    end)
  end

  def create(creator, _, attrs) when is_map(attrs) do
    create(creator, attrs)
  end

  @spec create(any(), attrs :: map) :: {:ok, Geolocation.t()} | {:error, Changeset.t()}
  def create(creator, attrs) when is_map(attrs) do
    repo().transact_with(fn ->
      with {:ok, attrs} <- resolve_mappable_address(attrs),
           {:ok, item} <- insert_geolocation(creator, attrs),
           {:ok, character} <- {:ok, nil} # FIXME: Characters.create(creator, attrs, item),
          #  act_attrs = %{verb: "created", is_local: true},
          #  {:ok, activity} <- Activities.create(creator, item, act_attrs),
          #  :ok <- publish(creator, item, activity, :created)
           do
        {:ok, populate_result(item, character)}
      end
    end)
  end

  defp insert_geolocation(creator, context, attrs) do
    cs = Geolocation.create_changeset(creator, context, attrs)

    with {:ok, item} <- repo().insert(cs) do
      {:ok, %{item | context: context}}
    end
  end

  defp insert_geolocation(creator, attrs) do
    cs = Geolocation.create_changeset(creator, attrs)
    with {:ok, item} <- repo().insert(cs), do: {:ok, item}
  end

  def thing_add_location(user, thing, mappable_address) when is_binary(mappable_address) do
    with {:ok, geolocation} <- create(user, %{name: mappable_address, mappable_address: mappable_address}) do
      if Utils.module_exists?(Bonfire.Tag.Tags) do
        Bonfire.Tag.Tags.tag_something(user, thing, geolocation)
      end
    end
  end


  # defp publish(creator, context, geolocation, activity, :created) do
  #   feeds = [
  #     CommonsPub.Feeds.outbox_id(context),
  #     CommonsPub.Feeds.outbox_id(creator),
  #     CommonsPub.Feeds.outbox_id(geolocation),
  #     Feeds.instance_outbox_id()
  #   ]

  #   with :ok <- FeedActivities.publish(activity, feeds) do
  #     ap_publish("create", geolocation.id, creator.id)
  #   end
  # end

  # defp publish(creator, geolocation, activity, :created) do
  #   feeds = [
  #     CommonsPub.Feeds.outbox_id(creator),
  #     CommonsPub.Feeds.outbox_id(geolocation),
  #     Feeds.instance_outbox_id()
  #   ]

  #   with :ok <- FeedActivities.publish(activity, feeds) do
  #     ap_publish("create", geolocation.id, Bonfire.Common.Utils.maybe_get(creator, :id))
  #   end
  # end

  # defp ap_publish(verb, context_id, user_id) do
  #   job_result =
  #     APPublishWorker.enqueue(verb, %{
  #       "context_id" => context_id,
  #       "user_id" => user_id
  #     })

  #   with {:ok, _} <- job_result, do: :ok
  # end

  # defp ap_publish(_, _, _), do: :ok

  @spec update(any(), Geolocation.t(), attrs :: map) ::
          {:ok, Geolocation.t()} | {:error, Changeset.t()}
  def update(user, %Geolocation{} = geolocation, attrs) do
    with {:ok, attrs} <- resolve_mappable_address(attrs),
         {:ok, item} <- repo().update(Geolocation.update_changeset(geolocation, attrs))
        # FIXME :ok <- ap_publish("update", item.id, user.id)
         do
      {:ok, populate_coordinates(item)}
    end
  end

  @spec soft_delete(any(), Geolocation.t()) :: {:ok, Geolocation.t()} | {:error, Changeset.t()}
  def soft_delete(%{} = user, %Geolocation{} = geo) do
    repo().transact_with(fn ->
      with {:ok, geo} <- Bonfire.Repo.Delete.soft_delete(geo)
          # FIXME :ok <- ap_publish("delete", geo.id, user.id)
           do
        {:ok, geo}
      end
    end)
  end

  def populate_result(geo, character) do
    populate_coordinates(%{geo | character: character})
  end

  def populate_coordinates(%Geolocation{geom: geom} = geo) when not is_nil(geom) do
    {lat, long} = geo.geom.coordinates

    %{geo | lat: lat, long: long}
  end

  def populate_coordinates(geo), do: geo || %{}

  def resolve_mappable_address(%{mappable_address: address} = attrs) when is_binary(address) do
    with {:ok, coords} <- Geocoder.call(address) do
      # IO.inspect(attrs)
      # IO.inspect(coords)
      # TODO: should take bounds and save in `geom`
      {:ok, Map.put(Map.put(attrs, :lat, coords.lat), :long, coords.lon)}
    else
      _ -> {:ok, attrs}
    end
  end

  def resolve_mappable_address(attrs), do: {:ok, attrs}
end
