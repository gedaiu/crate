module crate.auth.usercollection;

import std.exception;
import std.algorithm;
import std.stdio;
import std.array;
import std.datetime;

import crate.base;
import crate.error;

import vibe.data.json;

import vibeauth.users;
import vibeauth.collection;
import vibeauth.token;

class UserCrateCollection: UserCollection
{
  immutable(string[]) accessList;

  private Crate!UserData crate;

	this(immutable(string[]) accessList, Crate!UserData crate) {
		this.accessList = accessList;
    this.crate = crate;
	}

  private Json getUserData(string email) {
      auto users = crate.get.where("email", email).limit(1).exec;
      enforce!CrateNotFoundException(users.length == 1, "The user does not exist.");

      return users[0];
  }

  void disempower(string email, string access) {
    auto user = getUserData(email);

    enforce!CrateValidationException(accessList.canFind(access), "Unknown access");

    auto scopes = cast(Json[])(user["scopes"]);

    enforce!CrateValidationException(
      canFind(scopes, Json(access)),
      "The user already has this access");

    user["scopes"] = Json(scopes.filter!(a => a != access).array);

    crate.updateItem(user);
  }

  override {
    Token createToken(string email, SysTime expire, string[] scopes = [], string type = "Bearer") {
      auto user = opIndex(email);
      auto token = user.createToken(expire, scopes, type);

      crate.updateItem(user.toJson);

      return token;
    }

    void revoke(string token) {
      auto user = byToken(token);
      user.revoke(token);

      crate.updateItem(user.toJson);
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
      auto users = crate.get.whereArrayFieldContains("tokens", "name", token).limit(1).exec;

      enforce!CrateNotFoundException(users.length == 1, "Invalid token.");

      return new User(users[0].deserializeJson!UserData);
  	}

    bool contains(string email) {
      return crate.get.where("email", email).limit(1).exec.length == 1;
    }

    void add(User item) {
      crate.addItem(item.toJson);
    }

    void remove(const(string) id) {
      crate.deleteItem(id);
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

    ICollection!User save() {
      assert(false, "not implemented");
    }
  }
}

version(unittest) {
  import crate.collection.memory;

  auto userJson = `{
    "_id": "1",
    "email": "test@asd.asd",
    "password": "password",
    "salt": "salt",
    "scopes": ["scopes"],
    "tokens": [ { "name": "token", "expire": "2100-01-01T00:00:00", "type": "Bearer", "scopes": [] } ],
  }`;
}

@("it should find the users")
unittest
{
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
  auto crate = new MemoryCrate!UserData;
  crate.addItem(userJson.parseJsonString);

  auto collection = new UserCrateCollection(["access1"], crate);
  collection.empower("test@asd.asd", "access1");

  assert(crate.get.where("email", "test@asd.asd").limit(1).exec[0]["scopes"].length == 2);
  assert(crate.get.where("email", "test@asd.asd").limit(1).exec[0]["scopes"][1] == "access1");

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

@("it should disempower an user")
unittest
{
  auto crate = new MemoryCrate!UserData;
  crate.addItem(userJson.parseJsonString);

  auto collection = new UserCrateCollection(["scopes"], crate);
  collection.disempower("test@asd.asd", "scopes");

  assert(crate.get.where("email", "test@asd.asd").limit(1).exec[0]["scopes"].length == 0);

  bool found = true;
  try {
    collection.disempower("test@asd.asd", "invalid_access");
  } catch(CrateValidationException e) {
    found = false;
  }

  assert(!found, "It should not remove missing access");
}

@("it should generate user tokens")
unittest
{
  auto crate = new MemoryCrate!UserData;
  crate.addItem(userJson.parseJsonString);

  auto collection = new UserCrateCollection(["scopes"], crate);
  auto token = collection.createToken("test@asd.asd", Clock.currTime + 3600.seconds);

  assert(crate.get.where("email", "test@asd.asd").limit(1).exec[0]["tokens"].length == 2);
  assert(crate.get.where("email", "test@asd.asd").limit(1).exec[0]["tokens"][1]["name"] == token.name);
}

@("it should find user by token")
unittest
{
  auto userJson2 = `{
    "_id": 1,
    "email": "test2@asd.asd",
    "password": "password",
    "salt": "salt",
    "scopes": ["scopes"],
    "tokens": [{ "name": "token2", "expire": "2100-01-01T00:00:00", "type": "Bearer", "scopes": [] }],
  }`;

  auto crate = new MemoryCrate!UserData;

  crate.addItem(userJson2.parseJsonString);
  crate.addItem(userJson.parseJsonString);

  auto collection = new UserCrateCollection(["scopes"], crate);

  assert(collection.byToken("token2").email == "test2@asd.asd");
}

@("it should check if contains user")
unittest
{
  auto crate = new MemoryCrate!UserData;

  crate.addItem(userJson.parseJsonString);

  auto collection = new UserCrateCollection(["scopes"], crate);

  assert(collection.contains("test@asd.asd"));
  assert(!collection.contains("other@asd.asd"));
}

@("it should add an user")
unittest
{
  auto user = User.fromJson(userJson.parseJsonString);
  auto crate = new MemoryCrate!UserData;
  auto collection = new UserCrateCollection(["scopes"], crate);

  assert(!collection.contains("test@asd.asd"));
  collection.add(user);
  assert(collection.contains("test@asd.asd"));
}

@("it should delete an user")
unittest
{
  auto crate = new MemoryCrate!UserData;
  crate.addItem(userJson.parseJsonString);
  auto collection = new UserCrateCollection(["scopes"], crate);

  assert(collection.contains("test@asd.asd"));
  collection.remove("1");
  assert(!collection.contains("test@asd.asd"));
}
