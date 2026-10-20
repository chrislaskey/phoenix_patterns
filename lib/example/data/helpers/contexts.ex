defmodule Example.Data.Helpers.Contexts do
  import Ecto.Query

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

  def filter(query, key, value) do
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

  def sort(query, direction, field) do
    order_by(query, ^Keyword.new([{direction, field}]))
  end
end
