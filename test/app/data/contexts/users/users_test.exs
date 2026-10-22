defmodule App.Data.UsersTest do
  use App.DataCase

  import App.Data.UsersFixtures

  alias App.Data.User
  alias App.Data.Users

  describe "get_by/2" do
    test "does not return the user if the email does not exist" do
      refute Users.get_by(email: "unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Users.get_by(email: user.email)
    end
  end

  describe "get/2 and fetch/2" do
    test "return nothing for an unknown id" do
      refute Users.get(-1)
      assert Users.fetch(-1) == {:error, :not_found}
    end

    test "return the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Users.get(user.id)
      assert {:ok, %User{id: ^id}} = Users.fetch(user.id)
    end
  end

  describe "create/2 with registration_changeset/3" do
    test "requires email to be set" do
      {:error, changeset} = Users.create(%{}, changesets: &User.registration_changeset/3)

      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates email when given" do
      {:error, changeset} =
        Users.create(%{email: "not valid"}, changesets: &User.registration_changeset/3)

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates maximum values for email for security" do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Users.create(%{email: too_long}, changesets: &User.registration_changeset/3)

      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness" do
      %{email: email} = user_fixture()

      {:error, changeset} =
        Users.create(%{email: email}, changesets: &User.registration_changeset/3)

      assert "has already been taken" in errors_on(changeset).email

      # Now try with the uppercased email too, to check that email case is ignored.
      {:error, changeset} =
        Users.create(%{email: String.upcase(email)}, changesets: &User.registration_changeset/3)

      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers users without password" do
      email = unique_user_email()

      {:ok, user} =
        Users.create(valid_user_attributes(email: email),
          changesets: &User.registration_changeset/3
        )

      assert user.email == email
      assert is_nil(user.hashed_password)
      assert is_nil(user.confirmed_at)
      assert is_nil(user.password)
    end
  end

  describe "create/2, update/3 and change/3 without :changesets" do
    test "raise, a user has no default changeset" do
      message = ~r/User has no changeset\/3, pass the changesets/

      assert_raise ArgumentError, message, fn -> Users.create(valid_user_attributes()) end
      assert_raise ArgumentError, message, fn -> Users.update(user_fixture(), %{}) end
      assert_raise ArgumentError, message, fn -> Users.change(%User{}) end
    end
  end

  describe "change/3 with email_changeset/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} =
               changeset = Users.change(%User{}, %{}, changesets: &User.email_changeset/3)

      assert changeset.required == [:email]
    end
  end

  describe "change/3 with password_changeset/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} =
               changeset = Users.change(%User{}, %{}, changesets: &User.password_changeset/3)

      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Users.change(
          %User{},
          %{
            "password" => "new valid password"
          },
          changesets: &User.password_changeset/3,
          hash_password: false
        )

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update/3 with a list of changesets" do
    test "applies each in turn" do
      user = unconfirmed_user_fixture()

      assert {:ok, user} =
               Users.update(user, %{password: "new valid password"},
                 changesets: [&User.password_changeset/3, &User.confirm_changeset/3]
               )

      assert user.confirmed_at
      assert user.hashed_password
      assert Repo.reload!(user).confirmed_at == user.confirmed_at
    end
  end

  describe "inspect/2 for the User module" do
    test "does not include password" do
      refute inspect(%User{password: "123456"}) =~ "password: \"123456\""
    end
  end
end
