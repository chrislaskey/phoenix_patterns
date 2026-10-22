defmodule App.Data.UserTokensTest do
  use App.DataCase

  import App.Data.UsersFixtures

  alias App.Data.UserToken
  alias App.Data.UserTokens

  setup do
    user = user_fixture()
    %{user: user, params: %{user_id: user.id, sent_to: user.email, context: "login"}}
  end

  describe "create/2" do
    test "returns the token and stores its hash", %{user: user, params: params} do
      assert {:ok, %UserToken{} = user_token} = UserTokens.create(params)

      assert is_binary(user_token.encoded)

      assert user_token.token ==
               :crypto.hash(:sha256, Base.url_decode64!(user_token.encoded, padding: false))

      assert user_token.sent_to == user.email
      assert user_token.user_id == user.id
      refute Repo.reload!(user_token).encoded
    end

    test "stores a session token as is", %{user: user} do
      assert {:ok, %UserToken{} = user_token} =
               UserTokens.create(%{user_id: user.id, context: "session"})

      refute user_token.encoded
      assert Repo.reload!(user_token).token == user_token.token
    end

    test "redacts the token", %{params: params} do
      {:ok, user_token} = UserTokens.create(params)

      refute inspect(user_token) =~ user_token.encoded
      refute inspect(user_token) =~ inspect(user_token.token)
    end

    test "requires who and what the token is for" do
      assert {:error, changeset} = UserTokens.create(%{})
      assert %{context: _, user_id: _} = errors_on(changeset)
    end
  end

  describe "the :encoded_token filter" do
    test "finds the token by what the email carried", %{params: params} do
      {:ok, user_token} = UserTokens.create(params)

      assert %UserToken{id: id} =
               UserTokens.get_by([], filters: [encoded_token: user_token.encoded])

      assert id == user_token.id
    end

    test "matches nothing for another token or one that is not base64", %{params: params} do
      {:ok, _user_token} = UserTokens.create(params)

      refute UserTokens.get_by([],
               filters: [encoded_token: Base.url_encode64("other", padding: false)]
             )

      refute UserTokens.get_by([], filters: [encoded_token: "not base 64!"])
    end
  end

  describe "the :valid filter" do
    test "keeps a fresh magic link and drops an old one", %{params: params} do
      {:ok, user_token} = UserTokens.create(params)

      assert UserTokens.get_by([token: user_token.token], filters: [valid: true])

      offset_user_token(user_token.token, -16, :minute)
      refute UserTokens.get_by([token: user_token.token], filters: [valid: true])
      assert UserTokens.get_by(token: user_token.token)
    end

    test "gives an email change link a week", %{user: user, params: params} do
      {:ok, user_token} = UserTokens.create(%{params | context: "change:#{user.email}"})

      offset_user_token(user_token.token, -6, :day)
      assert UserTokens.get_by([token: user_token.token], filters: [valid: true])

      offset_user_token(user_token.token, -8, :day)
      refute UserTokens.get_by([token: user_token.token], filters: [valid: true])
    end

    test "gives a session two weeks", %{user: user} do
      {:ok, user_token} = UserTokens.create(%{user_id: user.id, context: "session"})

      offset_user_token(user_token.token, -13, :day)
      assert UserTokens.get_by([token: user_token.token], filters: [valid: true])

      offset_user_token(user_token.token, -15, :day)
      refute UserTokens.get_by([token: user_token.token], filters: [valid: true])
    end
  end

  describe "the :sent_to_user_email filter" do
    test "drops a token sent to a previous email of the user", %{user: user, params: params} do
      {:ok, user_token} = UserTokens.create(params)

      assert %UserToken{user: %{id: id}} =
               UserTokens.get_by([token: user_token.token],
                 filters: [sent_to_user_email: true],
                 preloads: [:user]
               )

      assert id == user.id

      Repo.update!(Ecto.Changeset.change(user, email: unique_user_email()))
      refute UserTokens.get_by([token: user_token.token], filters: [sent_to_user_email: true])
    end
  end

  describe "delete_many/1" do
    test "deletes the rows the filters select", %{user: user, params: params} do
      other = user_fixture()
      {:ok, _} = UserTokens.create(params)
      {:ok, _} = UserTokens.create(%{params | user_id: other.id, sent_to: other.email})

      assert {1, nil} = UserTokens.delete_many(filters: [user_id: user.id])
      assert [] = UserTokens.list(filters: [user_id: user.id])
      assert [_other_token] = UserTokens.list(filters: [user_id: other.id])
    end

    test "refuses to delete every row" do
      assert_raise ArgumentError, ~r/at least one filter/, fn -> UserTokens.delete_many([]) end

      assert_raise ArgumentError, ~r/at least one filter/, fn ->
        UserTokens.delete_many(filters: [])
      end
    end
  end
end
