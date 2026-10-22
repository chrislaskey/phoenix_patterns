defmodule App.Data.UserTokens do
  @moduledoc """
  The data context over `App.Data.UserToken`: sessions (context
  `"session"`), magic links (context `"login"`) and email change
  confirmations (context `"change:<current email>"`).

  `create/2` generates the token. A session token is stored as is, since it
  only ever lives in the signed session and cookie. A token sent by email
  is returned in `:encoded`, for the email, and the database only holds its
  hash, so anyone with read access to the table cannot use it. Look one up
  by what came back from the email with the `:encoded_token` filter, and
  refuse an expired one with `:valid`:

      {:ok, token} = UserTokens.create(%{user_id: user.id, sent_to: user.email, context: "login"})
      token.encoded
      UserTokens.get_by([context: "login"], filters: [encoded_token: encoded, valid: true])
  """

  use App.Data.Context, schema: App.Data.UserToken

  # Not imported: `Ecto.Query` has an `update/3` macro that would be expanded
  # where the context calls its own `update/3`. See `App.Data.Context`.
  require Ecto.Query

  @hash_algorithm :sha256
  @rand_size 32

  # It is very important to keep the magic link token expiry short,
  # since someone with access to the email may take over the account.
  @magic_link_validity_in_minutes 15
  @change_email_validity_in_days 7
  @session_validity_in_days 14

  # The default of `options` comes with the `create/1` of the context.
  def create(params, options) do
    token = :crypto.strong_rand_bytes(@rand_size)

    schema()
    |> struct()
    |> change(params, options)
    |> put_token(token)
    |> App.Repo.insert()
  end

  # The token as it came back from an email, matched against its hash. One
  # that `create/2` could not have encoded matches nothing.
  def filter(query, :encoded_token, encoded) do
    case decode(encoded) do
      {:ok, token} -> Ecto.Query.where(query, [row], row.token == ^hash(token))
      :error -> Ecto.Query.where(query, false)
    end
  end

  # A token that has not expired. A magic link is valid for a quarter of an
  # hour, an email change link for a week and a session for two weeks.
  def filter(query, :valid, true) do
    Ecto.Query.where(
      query,
      [token],
      (token.context == "login" and
         token.inserted_at > ago(^@magic_link_validity_in_minutes, "minute")) or
        (like(token.context, "change:%") and
           token.inserted_at > ago(^@change_email_validity_in_days, "day")) or
        (token.context == "session" and
           token.inserted_at > ago(^@session_validity_in_days, "day"))
    )
  end

  # A token sent to the email the user still has. A token sent to a previous
  # email of the user is refused, which the join to the user makes possible.
  def filter(query, :sent_to_user_email, true) do
    query
    |> join(:user)
    |> Ecto.Query.where([token, user: user], token.sent_to == user.email)
  end

  def filter(query, key, value), do: super(query, key, value)

  defp put_token(changeset, token) do
    case Ecto.Changeset.get_field(changeset, :context) do
      "session" -> Ecto.Changeset.change(changeset, token: token)
      _context -> Ecto.Changeset.change(changeset, token: hash(token), encoded: encode(token))
    end
  end

  defp hash(token), do: :crypto.hash(@hash_algorithm, token)
  defp encode(token), do: Base.url_encode64(token, padding: false)
  defp decode(encoded), do: Base.url_decode64(encoded, padding: false)
end
