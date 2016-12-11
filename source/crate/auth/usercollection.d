module crate.auth.usercollection;

import std.exception;
import std.algorithm;
import std.stdio;

import crate.base;
import crate.error;

import vibe.data.json;

import vibeauth.users;
import vibeauth.collection;

class UserCrateCollection: ICollection!User
{
  immutable(string[]) accessList;

  private Crate!UserData crate;

	this(immutable(string[]) accessList, Crate!UserData crate) {
		this.accessList = accessList;
    this.crate = crate;
	}

  private Json getUserData(string email) {
      auto users = crate.get("email", email, 1);
      enforce!CrateNotFoundException(users.length == 1, "The user does not exist.");

      return users[0];
  }

  User opIndex(string email) {
    return User.fromJson(getUserData(email));
	}

  void empower(string email, string access) {
    auto user = getUserData(email);

    enforce!CrateValidationException(accessList.canFind(access), "Unknown access");

    enforce!CrateValidationException(
      !canFind(cast(Json[])(user["scopes"]), Json(access)),
      "The user already has this access");

    user["scopes"] ~= Json(access);

    crate.updateItem(user);
  }

	User byToken(string token) {
		assert(false, "not implemented");
	}

  bool contains(string email) {
		assert(false, "not implemented");
  }

  void add(User item) {
    assert(false, "not implemented");
  }

  void remove(const(ulong) id) {
    assert(false, "not implemented");
  }

  ulong length() {
    assert(false, "not implemented");
  }

  int opApply(int delegate(User) dg) {
    assert(false, "not implemented");
  }

  int opApply(int delegate(ulong, User) dg) {
    assert(false, "not implemented");
  }

  bool empty() @property {
    assert(false, "not implemented");
  }

  Collection!(User) save() {
    assert(false, "not implemented");
  }
}

version(unittest) {
  import crate.collection.memory;

  auto userJson = `{
    "id": 1,
    "email": "test@asd.asd",
    "password": "password",
    "salt": "salt",
    "scopes": ["scopes"],
    "tokens": ["token"],
  }`;
}

@("it should find the users")
unittest
{
  auto user = User.fromJson(userJson.parseJsonString);
  auto crate = new MemoryCrate!UserData;
  crate.addItem(userJson.parseJsonString);

  auto collection = new UserCrateCollection([], crate);

  assert(collection["test@asd.asd"].email == "test@asd.asd");

  bool found = true;
  try {
    collection["other@asd.asd"];
  } catch(CrateNotFoundException e) {
    found = false;
  }

  assert(!found);
}

@("it should empower an user")
unittest
{
  auto user = User.fromJson(userJson.parseJsonString);
  auto crate = new MemoryCrate!UserData;
  crate.addItem(userJson.parseJsonString);

  auto collection = new UserCrateCollection(["access1"], crate);
  collection.empower("test@asd.asd", "access1");

  assert(crate.get("email", "test@asd.asd", 1)[0]["scopes"].length == 2);
  assert(crate.get("email", "test@asd.asd", 1)[0]["scopes"][1] == "access1");

  bool found = true;
  try {
    collection.empower("test@asd.asd", "invalid_access");
  } catch(CrateValidationException e) {
    found = false;
  }

  assert(!found, "It should not add the access");

  found = true;
  try {
    collection.empower("test@asd.asd", "access1");
  } catch(CrateValidationException e) {
    found = false;
  }

  assert(!found, "It should not add the the same access twice");
}
