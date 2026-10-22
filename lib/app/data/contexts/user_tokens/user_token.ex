defmodule App.Data.UserToken do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users_tokens" do
    # The token of a session, or the hash of a token sent by email, see
    # `App.Data.UserTokens`. An email token itself is only ever in
    # `encoded`, on the struct `create/2` returns, on its way into an email.
    field :token, :binary, redact: true
    field :encoded, :string, virtual: true, redact: true
    field :context, :string
    field :sent_to, :string
    field :authenticated_at, :utc_datetime
    belongs_to :user, App.Data.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @required [:context, :user_id]
  @optional [:sent_to, :authenticated_at]

  @doc """
  The row of a token: who it is for and what it is for.
  `App.Data.UserTokens.create/2` adds the token.
  """
  def changeset(token, params, _options \\ []) do
    token
    |> cast(params, @required ++ @optional)
    |> validate_required(@required)
  end
end
