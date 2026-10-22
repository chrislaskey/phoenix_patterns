defmodule App.Data.AccountsTest do
  use App.DataCase

  import App.Data.UsersFixtures

  alias App.Data.Accounts
  alias App.Data.User
  alias App.Data.UserToken

  describe "get_user_by_email_and_password/2" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture() |> set_password()
      refute Accounts.get_user_by_email_and_password(user.email, "invalid")
    end

    test "returns the user if the email and password are valid" do
      %{id: id} = user = user_fixture() |> set_password()

      assert %User{id: ^id} =
               Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end
  end

  describe "sudo_mode?/2" do
    test "validates the authenticated_at time" do
      now = DateTime.utc_now()

      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.utc_now()})
      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -21, :minute)})

      # minute override
      refute Accounts.sudo_mode?(
               %User{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute Accounts.sudo_mode?(%User{})
    end
  end

  describe "deliver_user_update_email_instructions/3" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(user, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "change:current@example.com"
    end
  end

  describe "update_user_email/2" do
    setup do
      user = unconfirmed_user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{user: user, token: token, email: email}
    end

    test "updates the email with a valid token", %{user: user, token: token, email: email} do
      assert {:ok, %{email: ^email}} = Accounts.update_user_email(user, token)
      changed_user = Repo.get!(User, user.id)
      assert changed_user.email != user.email
      assert changed_user.email == email
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email with invalid token", %{user: user} do
      assert Accounts.update_user_email(user, "oops") ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email with a token that is not base64", %{user: user} do
      assert Accounts.update_user_email(user, "not base 64!") ==
               {:error, :transaction_aborted}
    end

    test "does not update email if user email changed", %{user: user, token: token} do
      assert Accounts.update_user_email(%{user | email: "current@example.com"}, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      assert Accounts.update_user_email(user, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "update_user_password/2" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.update_user_password(user, %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{user: user} do
      {:ok, {user, expired_tokens}} =
        Accounts.update_user_password(user, %{
          password: "new valid password"
        })

      assert expired_tokens == []
      assert is_nil(user.password)
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)
      _ = generate_user_magic_link_token(user)

      {:ok, {_, _}} =
        Accounts.update_user_password(user, %{
          password: "new valid password"
        })

      refute Repo.get_by(UserToken, user_id: user.id, context: "session")
      refute Repo.get_by(UserToken, user_id: user.id, context: "login")
    end

    test "keeps the user's API tokens", %{user: user} do
      encoded_token = Accounts.generate_user_api_token(user)

      {:ok, {_, expired_tokens}} =
        Accounts.update_user_password(user, %{
          password: "new valid password"
        })

      refute Enum.any?(expired_tokens, &(&1.context == "api"))
      assert Accounts.get_user_api_token(encoded_token)
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"
      assert user_token.authenticated_at != nil

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end

    test "duplicates the authenticated_at of given user in new token", %{user: user} do
      user = %{user | authenticated_at: DateTime.add(DateTime.utc_now(:second), -3600)}
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.authenticated_at == user.authenticated_at
      assert DateTime.compare(user_token.inserted_at, user.authenticated_at) == :gt
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert {session_user, token_inserted_at} = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
      assert session_user.authenticated_at != nil
      assert token_inserted_at != nil
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      dt = ~N[2020-01-01 00:00:00]
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: dt, authenticated_at: dt])
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "get_user_by_magic_link_token/1" do
    setup do
      user = user_fixture()
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)
      %{user: user, token: encoded_token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert session_user = Accounts.get_user_by_magic_link_token(token)
      assert session_user.id == user.id
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_magic_link_token("oops")
      refute Accounts.get_user_by_magic_link_token("not base 64!")
    end

    test "does not return user for expired token", %{token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_user_by_magic_link_token(token)
    end
  end

  describe "login_user_by_magic_link/1" do
    test "confirms user and expires tokens" do
      user = unconfirmed_user_fixture()
      refute user.confirmed_at
      {encoded_token, hashed_token} = generate_user_magic_link_token(user)

      assert {:ok, {user, [%{token: ^hashed_token}]}} =
               Accounts.login_user_by_magic_link(encoded_token)

      assert user.confirmed_at
    end

    test "returns user and (deleted) token for confirmed user" do
      user = user_fixture()
      assert user.confirmed_at
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)
      assert {:ok, {^user, []}} = Accounts.login_user_by_magic_link(encoded_token)
      # one time use only
      assert {:error, :not_found} = Accounts.login_user_by_magic_link(encoded_token)
    end

    test "does not log in with a token that is not base64" do
      assert {:error, :not_found} = Accounts.login_user_by_magic_link("not base 64!")
    end

    test "raises when unconfirmed user has password set" do
      user = unconfirmed_user_fixture()
      {1, nil} = Repo.update_all(User, set: [hashed_password: "hashed"])
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)

      assert_raise RuntimeError, ~r/magic link log in is not allowed/, fn ->
        Accounts.login_user_by_magic_link(encoded_token)
      end
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "generate_user_api_token/1" do
    test "stores only the hash of the token it returns" do
      user = user_fixture()
      encoded_token = Accounts.generate_user_api_token(user)

      refute Repo.get_by(UserToken, token: Base.url_decode64!(encoded_token, padding: false))

      hashed_token = :crypto.hash(:sha256, Base.url_decode64!(encoded_token, padding: false))
      assert user_token = Repo.get_by(UserToken, token: hashed_token)
      assert user_token.context == "api"
      assert user_token.user_id == user.id
    end
  end

  describe "get_user_api_token/1" do
    setup do
      user = user_fixture()
      %{user: user, encoded_token: Accounts.generate_user_api_token(user)}
    end

    test "returns the token with its user", %{user: user, encoded_token: encoded_token} do
      assert %UserToken{user: %User{id: user_id}} = Accounts.get_user_api_token(encoded_token)
      assert user_id == user.id
    end

    test "does not return a malformed or unknown token" do
      refute Accounts.get_user_api_token("oops")
      refute Accounts.get_user_api_token(Base.url_encode64(:crypto.strong_rand_bytes(32)))
    end

    test "does not return a session token as an API token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      refute Accounts.get_user_api_token(Base.url_encode64(token, padding: false))
    end

    test "does not return an expired token", %{encoded_token: encoded_token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~U[2020-01-01 00:00:00Z]])
      refute Accounts.get_user_api_token(encoded_token)
    end
  end

  describe "update_user_api_token/2" do
    test "replaces the token with a new one" do
      user = user_fixture()
      encoded_token = Accounts.generate_user_api_token(user)
      user_token = Accounts.get_user_api_token(encoded_token)

      assert {:ok, {new_token, new_user_token, deleted_token}} =
               Accounts.update_user_api_token(user_scope_fixture(user), user_token)

      assert deleted_token.id == user_token.id
      assert new_user_token.id == Accounts.get_user_api_token(new_token).id
      refute Accounts.get_user_api_token(encoded_token)
      assert Accounts.get_user_api_token(new_token).user.id == user.id
    end

    test "does not update another user's token" do
      encoded_token = Accounts.generate_user_api_token(user_fixture())
      user_token = Accounts.get_user_api_token(encoded_token)

      assert {:error, :not_found} =
               Accounts.update_user_api_token(user_scope_fixture(), user_token)

      assert Accounts.get_user_api_token(encoded_token)
    end
  end

  describe "delete_user_api_token/2" do
    test "deletes only an API token of the scope's user" do
      user = user_fixture()
      encoded_token = Accounts.generate_user_api_token(user)
      user_token = Accounts.get_user_api_token(encoded_token)

      assert {:error, :not_found} = Accounts.delete_user_api_token(user_scope_fixture(), user_token)
      assert Accounts.get_user_api_token(encoded_token)

      assert {:ok, _} = Accounts.delete_user_api_token(user_scope_fixture(user), user_token)
      refute Accounts.get_user_api_token(encoded_token)
    end
  end

  describe "deliver_login_instructions/2" do
    setup do
      %{user: unconfirmed_user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "login"
    end
  end
end
