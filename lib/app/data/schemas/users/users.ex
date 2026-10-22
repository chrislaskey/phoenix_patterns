defmodule App.Data.Users do
  @moduledoc """
  The data context over `App.Data.User`: `App.Data.Context` and nothing
  else.

  `App.Data.User` has no single `changeset/3`, so `create/2`, `update/3`
  and `change/3` need the `:changesets` option with the changeset functions
  to apply, for example `&User.registration_changeset/3`. Flows that span
  users and their tokens, such as logging in by magic link, live in
  `App.Data.Accounts`.
  """

  use App.Data.Context, schema: App.Data.User
end
