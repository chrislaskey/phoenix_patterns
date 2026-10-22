defmodule App.Data.Helpers.Contexts do
  @moduledoc "Common helper functions for contexts"

  import Ecto.Query

  # Joins

  def joins(query, default, options, callback) do
    options
    |> Keyword.get(:joins, default)
    |> Enum.reduce(query, fn name, query ->
      callback.(query, name)
    end)
  end

  def join_by_any_schema_association(query, name) do
    if Ecto.Query.has_named_binding?(query, name) do
      query
    else
      join(query, :left, [root], new in assoc(root, ^name), as: ^name)
    end
  end

  # Preloads

  def preloads(query, default, options) do
    preloads = Keyword.get(options, :preloads, default)

    preload(query, ^preloads)
  end

  # Filters

  def filters(query, default, options, callback) do
    options
    |> Keyword.get(:filters, default)
    |> Enum.reduce(query, fn {key, value}, query ->
      callback.(query, key, value)
    end)
  end

  def filter_by_any_schema_fields(query, key, value) do
    where(query, ^Keyword.new([{key, value}]))
  end

  # Sorts

  def sorts(query, default, options, callback) do
    options
    |> Keyword.get(:order_by, default)
    |> Enum.reduce(query, fn
      {direction, field}, query -> callback.(query, direction, field)
      field, query -> callback.(query, :asc, field)
    end)
  end

  def sort_by_any_schema_fields(query, direction, field) do
    order_by(query, ^Keyword.new([{direction, field}]))
  end

  # Changesets

  def changeset(schema, record, params, options) do
    case Keyword.get(options, :changesets) do
      nil ->
        default_changeset(schema, record, params, options)

      changesets ->
        changesets
        |> List.wrap()
        |> Enum.reduce(record, fn changeset, record -> changeset.(record, params, options) end)
    end
  end

  defp default_changeset(schema, record, params, options) do
    if Code.ensure_loaded?(schema) and function_exported?(schema, :changeset, 3) do
      schema.changeset(record, params, options)
    else
      raise ArgumentError,
            "#{inspect(schema)} has no changeset/3, pass the changesets to apply in the :changesets option"
    end
  end
end
