defmodule App.Data.UserTokens do
  @moduledoc """
  The data context over `App.Data.UserToken`: sessions (context
  `"session"`), magic links (context `"login"`), email change
  confirmations (context `"change:<current email>"`) and websocket API
  clients (context `"api"`).

  `App.Data.Accounts` generates the tokens. Refuse an expired one with the
  `:valid` filter:

      UserTokens.get_by([token: token, context: "login"], filters: [valid: true])

  """

  use App.Data.Context, schema: App.Data.UserToken

  @magic_link_validity_in_minutes 15
  @change_email_validity_in_days 7
  @session_validity_in_days 14

  def filter(query, :valid, true) do
    # A token that has not expired. A magic link is valid for a quarter of an
    # hour, an email change link for a week, a session for two weeks and an
    # API token for a year.
    Ecto.Query.where(
      query,
      [token],
      (token.context == "login" and
         token.inserted_at > ago(^@magic_link_validity_in_minutes, "minute")) or
        (like(token.context, "change:%") and
           token.inserted_at > ago(^@change_email_validity_in_days, "day")) or
        (token.context == "session" and
           token.inserted_at > ago(^@session_validity_in_days, "day")) or
        (token.context == "api" and
           token.inserted_at > ago(^App.Data.UserToken.api_validity_in_days(), "day"))
    )
  end

  def filter(query, :sent_to_user_email, true) do
    # A token sent to the email the user still has. A token sent to a previous
    # email of the user is refused, which the join to the user makes possible.
    query
    |> join(:user)
    |> Ecto.Query.where([token, user: user], token.sent_to == user.email)
  end

  def filter(query, :except_context, context) do
    Ecto.Query.where(query, [token], token.context != ^context)
  end

  def filter(query, key, value), do: super(query, key, value)
end
