defmodule Example.Data.Context do
  @moduledoc """
  Common implementation for context functions. All database operations must go
  through the core Data contexts, so only universal logic that must always
  be run and always be validated should go through this. For use-case specific
  calls, make them in a separate module that calls this for the data layer
  actions.

  ## Examples

  Custom filters and sorts can be added by overriding the values:

    def filter(query, :hello, value), do: Ecto.Query.where(query, world: ^value)
    def filter(query, key, value), do: super(query, key, value)

  NOTE: the built-in `filter/3` function provides a dynamic fallback, matching
  key/value to schema fields. Make sure to include this clause if you want to
  continue using it.

  Or if you want to disable that functionality entirely, define this in the context:

    def filter(query, _key, _value), do: query

  ### Joins

  The `joins` key can be used to define named joins. The default implementation allows
  joining by any association defined in the schema. Joins can be referenced in
  other parts of the code, for example in a filter:

    use Example.Data.Context, joins: [:users], #...

    def filter(query, :user_id, value) do
      Ecto.Query.where(query, [users: users], users.id == ^value)
    end

  Custom `join` functions can also be defined for more complex associations not
  defined in the schema:

    use Example.Data.Context, joins: [:world], # ...

    def join(query, :world), do:
      query
      |> Ecto.Query.join(query, :left, [root], new in assoc(root, :hello), as: :hello)
      |> Ecto.Query.join(query, :left, [hello: hello], new in assoc(hello, :world), as: :world)
    end

    def filter(query, :world_id, value) do
      Ecto.Query.where(query, [world: world], world.id == ^value)
    end

    def filter(query, :world_slug, value) do
      Ecto.Query.where(query, [world: world], world.slug == ^value)
    end

  This defines a join once that every filter can then use, rather than (re)defining joins
  in the filter each time.

  """

  # Overridable

  @callback list(Keyword.t()) :: list(any())
  @callback join(map(), atom()) :: map()
  @callback filter(map(), atom(), any()) :: map()
  @callback sort(map(), atom(), any()) :: map()

  @callback get(String.t() | integer() | atom(), Keyword.t()) :: map() | nil
  @callback get_by(Keyword.t()) :: map() | nil
  @callback fetch(String.t() | integer() | atom(), Keyword.t()) :: {:ok, map()} | {:error, :not_found}
  @callback fetch_by(Keyword.t()) :: {:ok, map()} | {:error, :not_found}

  @callback change(struct(), map(), Keyword.t()) :: Ecto.Changeset.t()
  @callback create(map(), Keyword.t()) :: {:ok, map()} | {:error, any()}
  @callback update(struct(), map(), Keyword.t()) :: {:ok, map()} | {:error, any()}
  @callback get_or_create(String.t() | integer() | atom(), map(), Keyword.t()) ::
              {:ok, map()} | {:error, any()}
  @callback get_or_create_by(Keyword.t(), map(), Keyword.t()) :: {:ok, map()} | {:error, any()}
  @callback create_or_update(String.t() | integer() | atom(), map(), Keyword.t()) ::
              {:ok, map()} | {:error, any()}
  @callback create_or_update_by(Keyword.t(), map(), Keyword.t()) :: {:ok, map()} | {:error, any()}
  @callback delete(struct() | String.t() | integer()) :: {:ok, map()} | {:error, any()}
  @callback delete_by(Keyword.t()) :: {:ok, map()} | {:error, any()}
  @callback delete_many(Keyword.t()) :: {non_neg_integer(), nil | list(any())}

  # Not overridable

  @callback schema() :: atom()
  @callback joins() :: list(any())
  @callback preloads() :: list(any())
  @callback filters() :: list(any())
  @callback sorts() :: list(any())

  defmacro __using__(opts \\ []) do
    quote do
      @behaviour Example.Data.Context

      # List

      def list(options \\ []) do
        schema()
        |> Example.Data.Helpers.Contexts.joins(joins(), options, &join/2)
        |> Example.Data.Helpers.Contexts.preloads(preloads(), options)
        |> Example.Data.Helpers.Contexts.filters(filters(), options, &filter/3)
        |> Example.Data.Helpers.Contexts.sorts(sorts(), options, &sort/3)
        |> Example.Repo.all()
      end

      def join(query, name) do
        Example.Data.Helpers.Contexts.join_by_any_schema_association(query, name)
      end

      def filter(query, key, value) do
        Example.Data.Helpers.Contexts.filter_by_any_schema_fields(query, key, value)
      end

      def sort(query, direction, field) do
        Example.Data.Helpers.Contexts.sort_by_any_schema_fields(query, direction, field)
      end

      # Get/fetch

      def get(id, options \\ []) do
        schema()
        |> Example.Data.Helpers.Contexts.joins(joins(), options, &join/2)
        |> Example.Data.Helpers.Contexts.preloads(preloads(), options)
        |> Example.Data.Helpers.Contexts.filters(filters(), options, &filter/3)
        |> Example.Repo.get(id)
      end

      def get_by(values, options \\ []) do
        schema()
        |> Example.Data.Helpers.Contexts.joins(joins(), options, &join/2)
        |> Example.Data.Helpers.Contexts.preloads(preloads(), options)
        |> Example.Data.Helpers.Contexts.filters(filters(), options, &filter/3)
        |> Example.Repo.get_by(values)
      end

      def fetch(id, options \\ []) do
        case get(id, options) do
          nil -> {:error, :not_found}
          value -> {:ok, value}
        end
      end

      def fetch_by(values, options \\ []) do
        case get_by(values, options) do
          nil -> {:error, :not_found}
          value -> {:ok, value}
        end
      end

      # Change

      def change(record, params \\ %{}, options \\ []) do
        Example.Data.Helpers.Contexts.changeset(schema(), record, params, options)
      end

      # Create

      def create(params, options \\ []) do
        schema()
        |> struct()
        |> change(params, options)
        |> Example.Repo.insert()
      end

      # Update

      def update(record, params, options \\ []) do
        record
        |> change(params, options)
        |> Example.Repo.update()
      end

      # Get or create

      def get_or_create(id, params, options \\ [])
      def get_or_create(%{id: id}, params, options), do: get_or_create(id, params, options)
      def get_or_create(%{"id" => id}, params, options), do: get_or_create(id, params, options)

      def get_or_create(id, params, options) do
        case get(id, options) do
          nil -> create(params, options)
          record -> record
        end
      end

      def get_or_create_by(by, params, options \\ []) do
        case get_by(by, options) do
          nil -> create(params, options)
          record -> record
        end
      end

      # Create or update

      def create_or_update(id, params, options \\ [])
      def create_or_update(%{id: id}, params, options), do: create_or_update(id, params, options)
      def create_or_update(%{"id" => id}, params, options), do: create_or_update(id, params, options)

      def create_or_update(id, params, options) do
        case get(id, options) do
          nil -> create(params, options)
          record -> update(record, params, options)
        end
      end

      def create_or_update_by(by, params, options \\ []) do
        case get_by(by, options) do
          nil -> create(params, options)
          record -> update(record, params, options)
        end
      end

      # Delete

      def delete(record) when is_map(record) do
        Example.Repo.delete(record)
      end

      def delete(id) do
        case fetch(id) do
          {:ok, record} -> delete(record)
          error -> error
        end
      end

      def delete_by(by) do
        case fetch_by(by) do
          {:ok, record} -> delete(record)
          error -> error
        end
      end

      def delete_many(options) do
        if Keyword.get(options, :filters) == nil || Keyword.get(options, :filters) == [] do
          raise ArgumentError, "delete_many/1 needs at least one filter, it would delete every row"
        end

        schema()
        |> Example.Data.Helpers.Contexts.joins(joins(), options, &join/2)
        |> Example.Data.Helpers.Contexts.filters(filters(), options, &filter/3)
        |> Example.Repo.delete_all()
      end

      # Macro functions

      def schema, do: get_opt(:schema)
      def joins, do: get_opt(:joins, [])
      def preloads, do: get_opt(:preloads, [])
      def filters, do: get_opt(:filters, [])
      def sorts, do: get_opt(:sorts, [])

      # Macro helpers

      defp get_opt(key, default \\ nil) do
        Keyword.get(unquote(opts), key, default)
      end

      defoverridable list: 1,
                     join: 2,
                     filter: 3,
                     sort: 3,
                     get: 2,
                     get_by: 2,
                     fetch: 2,
                     fetch_by: 2,
                     change: 3,
                     create: 2,
                     update: 3,
                     get_or_create: 3,
                     get_or_create_by: 3,
                     create_or_update: 3,
                     create_or_update_by: 3,
                     delete: 1,
                     delete_by: 1,
                     delete_many: 1
    end
  end
end
