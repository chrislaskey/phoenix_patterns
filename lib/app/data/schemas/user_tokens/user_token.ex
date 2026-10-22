defmodule App.Data.UserToken do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users_tokens" do
    # The token of a session, or the hash of a token sent by email or given
    # to an API client, see `App.Data.Accounts`.
    field :token, :binary, redact: true
    field :context, :string
    field :sent_to, :string
    field :authenticated_at, :utc_datetime
    belongs_to :user, App.Data.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @required [:token, :context, :user_id]
  @optional [:sent_to, :authenticated_at]

  @doc """
  The row of a token: the token, who it is for and what it is for.
  """
  def changeset(token, params, _options \\ []) do
    token
    |> cast(params, @required ++ @optional)
    |> validate_required(@required)
  end
end
