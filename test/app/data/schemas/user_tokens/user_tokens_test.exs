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
    test "stores the token it is given", %{user: user, params: params} do
      token = new_token()

      assert {:ok, %UserToken{} = user_token} = UserTokens.create(Map.put(params, :token, token))

      assert Repo.reload!(user_token).token == token
      assert user_token.sent_to == user.email
      assert user_token.user_id == user.id
    end

    test "redacts the token", %{params: params} do
      {:ok, user_token} = UserTokens.create(Map.put(params, :token, new_token()))

      refute inspect(user_token) =~ inspect(user_token.token)
    end

    test "requires the token and who and what it is for" do
      assert {:error, changeset} = UserTokens.create(%{})
      assert %{token: _, context: _, user_id: _} = errors_on(changeset)
    end
  end

  describe "the :valid filter" do
    test "keeps a fresh magic link and drops an old one", %{params: params} do
      {:ok, user_token} = UserTokens.create(Map.put(params, :token, new_token()))

      assert UserTokens.get_by([token: user_token.token], filters: [valid: true])

      offset_user_token(user_token.token, -16, :minute)
      refute UserTokens.get_by([token: user_token.token], filters: [valid: true])
      assert UserTokens.get_by(token: user_token.token)
    end

    test "gives an email change link a week", %{user: user, params: params} do
      {:ok, user_token} =
        UserTokens.create(Map.merge(params, %{context: "change:#{user.email}", token: new_token()}))

      offset_user_token(user_token.token, -6, :day)
      assert UserTokens.get_by([token: user_token.token], filters: [valid: true])

      offset_user_token(user_token.token, -8, :day)
      refute UserTokens.get_by([token: user_token.token], filters: [valid: true])
    end

    test "gives a session two weeks", %{user: user} do
      {:ok, user_token} = UserTokens.create(%{user_id: user.id, context: "session", token: new_token()})

      offset_user_token(user_token.token, -13, :day)
      assert UserTokens.get_by([token: user_token.token], filters: [valid: true])

      offset_user_token(user_token.token, -15, :day)
      refute UserTokens.get_by([token: user_token.token], filters: [valid: true])
    end
  end

  describe "the :sent_to_user_email filter" do
    test "drops a token sent to a previous email of the user", %{user: user, params: params} do
      {:ok, user_token} = UserTokens.create(Map.put(params, :token, new_token()))

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
      {:ok, _} = UserTokens.create(Map.put(params, :token, new_token()))

      {:ok, _} =
        UserTokens.create(Map.merge(params, %{user_id: other.id, sent_to: other.email, token: new_token()}))

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

  defp new_token, do: :crypto.strong_rand_bytes(32)
end
