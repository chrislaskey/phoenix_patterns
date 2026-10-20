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
    def filter(query, key, value), do: Helpers.Contexts.filter(query, key, value)

  NOTE: the built-in `filter/3` function provides a dynamic fallback, matching
  key/value to schema fields. Make sure to include this clause if you want to
  continue using it.

  Or if you want to disable that functionality entirely, define this in the context:

    def filter(query, _key, _value), do: query

  """

  # Overridable

  @callback list(Keyword.t()) :: list(any())
  @callback filter(map(), atom(), any()) :: map()
  @callback sort(map(), atom(), any()) :: map()

  @callback get(String.t() | integer() | atom(), Keyword.t()) :: map() | nil
  @callback get_by(Keyword.t()) :: map() | nil
  @callback fetch(String.t() | integer() | atom(), Keyword.t()) :: {:ok, map()} | {:error, :not_found}
  @callback fetch_by(Keyword.t())  :: {:ok, map()} | {:error, :not_found}

  # Not overridable

  @callback schema() :: atom()
  @callback preloads() :: list(any())
  @callback filters() :: list(any())
  @callback sorts() :: list(any())

  defmacro __using__(opts \\ []) do
    quote do
      @behaviour Example.Data.Context

      # List

      def list(options \\ []) do
        schema()
        |> Example.Data.Helpers.Contexts.preloads(preloads(), options)
        |> Example.Data.Helpers.Contexts.filters(filters(), options, &filter/3)
        |> Example.Data.Helpers.Contexts.sorts(sorts(), options, &sort/3)
        |> Example.Repo.all()
      end

      def filter(query, key, value) do
        Example.Data.Helpers.Contexts.filter(query, key, value)
      end

      def sort(query, direction, field) do
        Example.Data.Helpers.Contexts.sort(query, direction, field)
      end

      # Get/fetch

      def get(id, options \\ []) do
        schema()
        |> Example.Data.Helpers.Contexts.preloads(preloads(), options)
        |> Example.Repo.get(id)
      end

      def get_by(values, options \\ []) do
        schema()
        |> Example.Data.Helpers.Contexts.preloads(preloads(), options)
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

      # Macro functions

      def schema, do: get_opt(:schema)
      def preloads, do: get_opt(:preloads, [])
      def filters, do: get_opt(:filters, [])
      def sorts, do: get_opt(:sorts, [])

      # Macro helpers

      defp get_opt(key, default \\ nil) do
        Keyword.get(unquote(opts), key, default)
      end

      defoverridable [
        list: 1,
        filter: 3,
        sort: 3,
        get: 2,
        get_by: 2,
        fetch: 2,
        fetch_by: 2
      ]
    end
  end
end


