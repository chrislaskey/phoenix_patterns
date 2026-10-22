defmodule App.Data.Accounts do
  @moduledoc """
  Signing up, logging in and managing an account, over the
  `App.Data.Users` and `App.Data.UserTokens` contexts.

  The data contexts hold the single-table operations and nothing specific
  to a flow. This module holds the flows that span a user and their tokens,
  or the database and an email: logging in by magic link or password,
  sessions, changing the email with a confirmation link and changing the
  password. The web layer calls the data contexts directly for plain reads
  and form changesets, and this module for these flows.
  """

  alias App.Data.Accounts.Email
  alias App.Data.User
  alias App.Data.Users
  alias App.Data.UserToken
  alias App.Data.UserTokens
  alias App.Repo

  @login_context "login"
  @session_context "session"
  @api_context "api"

  @hash_algorithm :sha256
  @rand_size 32

  ## Passwords and sudo mode

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.add(DateTime.utc_now(), minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  ## Password log in

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Users.get_by(email: email)
    if valid_password?(user, password), do: user
  end

  ## Session

  @doc """
  Generates a session token.

  It is stored as is, since it only ever lives in the signed session and
  cookie.
  """
  def generate_user_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)

    {:ok, _user_token} =
      UserTokens.create(%{
        token: token,
        user_id: user.id,
        context: @session_context,
        authenticated_at: user.authenticated_at || DateTime.utc_now(:second)
      })

    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    case UserTokens.get_by([token: token, context: @session_context],
           filters: [valid: true],
           preloads: [:user]
         ) do
      %UserToken{user: user} = user_token ->
        {%{user | authenticated_at: user_token.authenticated_at}, user_token.inserted_at}

      nil ->
        nil
    end
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    UserTokens.delete_many(filters: [token: token, context: @session_context])
    :ok
  end

  ## API

  @doc """
  Generates an API token, for a client of the websocket API at `/api`.

  The token is returned encoded and only its hash is stored, so anyone with
  read access to the table cannot use it. The client keeps it and sends it
  on every connect, see `App.Web.ApiSocket`.
  """
  def generate_user_api_token(user) do
    {encoded_token, _user_token} = create_api_token(user)
    encoded_token
  end

  @doc """
  Gets the API token row of the given encoded token, with its user.

  Returns `nil` when the token is unknown, malformed or expired.
  """
  def get_user_api_token(encoded_token) do
    case decode(encoded_token) do
      {:ok, token} ->
        UserTokens.get_by([token: hash(token), context: @api_context],
          filters: [valid: true],
          preloads: [:user]
        )

      :error ->
        nil
    end
  end

  @doc """
  Updates an API token of the scope's user by replacing it: the token is
  deleted and a new one created in its place.

  Returns `{:ok, {encoded_token, new_token, deleted_token}}`, or
  `{:error, :not_found}` when the token is not one of the user's API tokens.
  """
  def update_user_api_token(scope, %UserToken{} = user_token) do
    Repo.transact(fn ->
      with {:ok, deleted_token} <- delete_user_api_token(scope, user_token) do
        {encoded_token, new_token} = create_api_token(scope.user)
        {:ok, {encoded_token, new_token, deleted_token}}
      end
    end)
  end

  @doc """
  Deletes an API token of the scope's user.

  Returns `{:error, :not_found}` when the token is not one of the user's
  API tokens.
  """
  def delete_user_api_token(scope, %UserToken{} = user_token) do
    case UserTokens.get_by(id: user_token.id, user_id: scope.user.id, context: @api_context) do
      %UserToken{} = user_token -> UserTokens.delete(user_token)
      nil -> {:error, :not_found}
    end
  end

  ## Magic link log in

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(encoded_token) do
    case get_magic_link_token(encoded_token) do
      %UserToken{user: user} -> user
      nil -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(encoded_token) do
    case get_magic_link_token(encoded_token) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      %UserToken{user: %User{confirmed_at: nil, hashed_password: hash}} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      %UserToken{user: %User{confirmed_at: nil} = user} ->
        update_user_and_delete_all_tokens(user, %{}, [&User.confirm_changeset/3])

      %UserToken{user: user} = token ->
        {:ok, _token} = UserTokens.delete(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    encoded_token = create_email_token(user, @login_context)

    Email.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  ## Email change

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    encoded_token = create_email_token(user, change_email_context(current_email))

    Email.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, encoded_token) do
    context = change_email_context(user.email)

    Repo.transact(fn ->
      with {:ok, token} <- decode(encoded_token),
           %UserToken{sent_to: email} <-
             UserTokens.get_by([token: hash(token), context: context], filters: [valid: true]),
           {:ok, user} <- Users.update(user, %{email: email}, changesets: &User.email_changeset/3),
           {_count, _result} <-
             UserTokens.delete_many(filters: [user_id: user.id, context: context]) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  ## Password change

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.
  Every token of the user is expired except their API tokens, which a
  client may hold on another machine.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    update_user_and_delete_all_tokens(user, attrs, [&User.password_changeset/3], except_context: @api_context)
  end

  ## Helpers

  defp get_magic_link_token(encoded_token) do
    case decode(encoded_token) do
      {:ok, token} ->
        UserTokens.get_by([token: hash(token), context: @login_context],
          filters: [valid: true, sent_to_user_email: true],
          preloads: [:user]
        )

      :error ->
        nil
    end
  end

  # The token goes into the email and only its hash into the database, so
  # anyone with read access to the table cannot use it. A token sent to an
  # email the user has since changed no longer matches (see the
  # `:sent_to_user_email` filter of `App.Data.UserTokens`).
  defp create_email_token(user, context) do
    token = :crypto.strong_rand_bytes(@rand_size)

    {:ok, _user_token} =
      UserTokens.create(%{token: hash(token), user_id: user.id, sent_to: user.email, context: context})

    encode(token)
  end

  defp create_api_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)

    {:ok, user_token} =
      UserTokens.create(%{token: hash(token), user_id: user.id, context: @api_context})

    {encode(token), user_token}
  end

  defp hash(token), do: :crypto.hash(@hash_algorithm, token)
  defp encode(token), do: Base.url_encode64(token, padding: false)
  defp decode(encoded), do: Base.url_decode64(encoded, padding: false)

  defp change_email_context(current_email), do: "change:#{current_email}"

  defp update_user_and_delete_all_tokens(user, params, changesets, filters \\ []) do
    Repo.transact(fn ->
      with {:ok, user} <- Users.update(user, params, changesets: changesets) do
        filters = [{:user_id, user.id} | filters]
        tokens_to_expire = UserTokens.list(filters: filters)

        UserTokens.delete_many(filters: filters)

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
