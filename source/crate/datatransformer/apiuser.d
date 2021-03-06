module crate.datatransformer.apiuser;

import std.algorithm;
import std.array;
import std.stdio;
import std.string;
import std.conv;
import std.exception;
import std.range.interfaces;

import vibe.inet.url;
import vibe.http.router;
import vibe.http.form;
import vibe.data.json;

import vibeauth.users;

import crate.collection.memory;
import crate.base;
import crate.ctfe;
import crate.collection.proxy;
import crate.error;

private {
  Json fromCrate(const Json data) {
    Json result = Json.emptyObject;

    result["_id"] = data["_id"];
    result["name"] = data["name"];
    result["username"] = data["username"];
    result["email"] = data["email"];

    return result;
  }

  Json toCrate(const Json data, const Json userData) {
    Json result = Json.emptyObject;

    result["_id"] = data["_id"];
    result["name"] = data["name"];
    result["username"] = data["username"];
    result["email"] = data["email"];

    result["isActive"] = userData["isActive"];
    result["password"] = userData["password"];
    result["salt"] = userData["salt"];
    result["scopes"] = userData["scopes"];
    result["tokens"] = userData["tokens"];

    return result;
  }
}

struct User {
  string _id;

  string name;
  string username;
  string email;

  Json toJson() const @safe {
    Json result = Json.emptyObject;

    result["_id"] = _id;
    result["name"] = name;
    result["username"] = username;
    result["email"] = email;

    return result;
  }

  static User fromJson(Json src) @safe {
    validateUserFields(src);

    User user;
    user._id = src["_id"].to!string;
    user.name = src["name"].to!string;
    user.username = src["username"].to!string;
    user.email = src["email"].to!string;

    return user;
  }
}

class ApiUserSelector: ProxySelector {

  this(ICrateSelector selector) {
    super(selector);
  }

  override InputRange!Json exec() {
    return super.exec.map!(a => a.fromCrate).inputRangeObject;
  }
}

class ApiUserTransformer: Crate!User {

  private {
    Crate!UserData crate;

    static immutable defaultSingular = Singular!UserData;
    static immutable defaultPlural = Plural!UserData;
  }

  this(Crate!UserData crate) {
    this.crate = crate;
  }

  @trusted:
    CrateConfig!User config() {
      CrateConfig!User config;

      config.getList = crate.config.getList;
      config.getItem = crate.config.getItem;
      config.addItem = crate.config.addItem;
      config.deleteItem = crate.config.deleteItem;
      config.replaceItem = crate.config.replaceItem;
      config.updateItem = crate.config.updateItem;

      config.singular = crate.config.singular == defaultSingular ? "user" : crate.config.singular;
      config.plural = crate.config.plural == defaultPlural ? "users" : crate.config.plural;

      return config;
    }

    ICrateSelector get() {
      return new ApiUserSelector(crate.get);
    }

    ICrateSelector getList() {
      auto data = crate.getList().exec.map!(a => a.fromCrate).array;

      return new CrateRange(data.array);
    }

    Json addItem(Json item) {
      validateUserFields(item);

      return crate.addItem(item);
    }

    ICrateSelector getItem(string id) {
      return new CrateRange(crate.getItem(id).exec.map!(a => a.fromCrate));
    }

    Json updateItem(Json item) {
      validateUserFields(item);

      auto dbItem = crate.getItem(item["_id"].to!string).exec.front;

      return crate.updateItem(item.toCrate(dbItem));
    }

    void deleteItem(string id) {
      crate.deleteItem(id);
    }
}

private void validateUserFields(Json data) @trusted {
  static immutable forbiddenFields = ["isActive", "password", "salt", "scopes", "tokens"];

  foreach(field; forbiddenFields) {
    enforce!CrateValidationException(data[field].type == Json.Type.undefined, "`" ~ field ~ "` must not be present.");
  }
}

version(unittest) {
  import fluentasserts.vibe.request;
  import fluentasserts.vibe.json;
  import fluent.asserts;
  import crate.http.router;
  import crate.api.rest.policy;
  import crate.base;

  ApiUserTransformer userCrate;
  MemoryCrate!UserData userDataCrate;

  auto getTestRoute() {
    CrateConfig!UserData config;
    auto router = new URLRouter();
    userDataCrate = new MemoryCrate!UserData(config);
    userCrate = new ApiUserTransformer(userDataCrate);

    router.crateSetup.add(userCrate, new UserTermFilter);

    return router;
  }

  auto userJson = `{
      "_id": 1,
      "email": "test2@asd.asd",
      "name": "test",
      "username": "test_user",
      "isActive": true,
      "password": "password",
      "salt": "salt",
      "scopes": ["scopes"],
      "tokens": [{ "name": "token2", "expire": "2100-01-01T00:00:00", "type": "Bearer", "scopes": [] }],
    }`;
}


@("it should replace the default names")
unittest
{
  CrateConfig!UserData config;

  auto router = new URLRouter();
  auto userCrate = new ApiUserTransformer(new MemoryCrate!UserData(config));

  userCrate.config.singular.should.equal("user");
  userCrate.config.plural.should.equal("users");
}

@("it should allow model name customization")
unittest
{
  CrateConfig!UserData config;
  config.singular = "person";
  config.plural = "persons";

  auto router = new URLRouter;
  auto userCrate = new ApiUserTransformer(new MemoryCrate!UserData(config));

  userCrate.config.singular.should.equal("person");
  userCrate.config.plural.should.equal("persons");
}

@("it should hide the sensible fields on GET")
unittest
{
  auto router = getTestRoute;
  userDataCrate.addItem(userJson.parseJsonString);

  request(router)
    .get("/users")
      .expectStatusCode(200)
      .end((Response response) => {
        response.bodyJson["users"].length.should.be.greaterThan(0);

        auto user = response.bodyJson["users"][0];
        user.keys.should.contain(["_id", "email", "name", "username"]);
        user.keys.should.not.contain(["isActive", "password", "salt", "scopes", "tokens"]);
        user["_id"].to!string.should.equal("1");
        user["email"].to!string.should.equal("test2@asd.asd");
        user["name"].to!string.should.equal("test");
        user["username"].to!string.should.equal("test_user");
      });

  request(router)
    .get("/users/1")
      .expectStatusCode(200)
      .end((Response response) => {
        auto user = response.bodyJson["user"];
        user.keys.should.contain(["_id", "email", "name", "username"]);
        user.keys.should.not.contain(["isActive", "password", "salt", "scopes", "tokens"]);

        user["_id"].to!string.should.equal("1");
        user["email"].to!string.should.equal("test2@asd.asd");
        user["name"].to!string.should.equal("test");
        user["username"].to!string.should.equal("test_user");
      });
}

@("it should not accept hidden fields on POST")
unittest
{
  auto router = getTestRoute;
  auto data = Json.emptyObject;
  data["user"] = userJson.parseJsonString;

  request(router)
    .post("/users")
      .send(data)
      .expectStatusCode(400)
      .end((Response response) => {
        response.bodyJson.keys.should.equal(["errors"]);
        userDataCrate.getList().exec.empty.should.equal(true);
      });
}

@("it should not accept hidden fields on PUT")
unittest
{
  auto router = getTestRoute;
  auto data = Json.emptyObject;

  userDataCrate.addItem(userJson.parseJsonString);

  data["user"] = userJson.parseJsonString;

  request(router)
    .put("/users/1")
      .send(data)
      .expectStatusCode(400)
      .end((Response response) => {
        auto userData = userDataCrate.getItem("1").exec.front;

        userData["_id"].should.equal("1");
        userData["email"].should.equal("test2@asd.asd");
        userData["name"].should.equal("test");
        userData["username"].should.equal("test_user");
        userData["isActive"].should.equal(true);
        userData["password"].should.equal("password");
        userData["salt"].should.equal("salt");

        userData["scopes"][0].should.equal("scopes");
        userData["tokens"].length.should.equal(1);
      });

  data["user"] = Json.emptyObject;
  data["user"]["email"] = "test@asd.asd";
  data["user"]["name"] = "test2";
  data["user"]["username"] = "test_user2";

  request(router)
    .put("/users/1")
      .send(data)
      .expectStatusCode(200)
      .end((Response response) => {
        auto userData = userDataCrate.getItem("1").exec.front;
        userData["_id"].to!string.should.equal("1");
        userData["email"].to!string.should.equal("test@asd.asd");
        userData["name"].to!string.should.equal("test2");
        userData["username"].to!string.should.equal("test_user2");
        userData["isActive"].to!string.should.equal("true");
        userData["password"].to!string.should.equal("password");
        userData["salt"].to!string.should.equal("salt");

        userData["scopes"][0].to!string.should.equal("scopes");
        userData["tokens"].length.should.equal(1);
      });
}


/// Filter designed to work with the getList operation. It will filter all the users
/// that have the "term" parameter in the email
class UserTermFilter {

  /// Call the "like" method on the crate selector
  ICrateSelector any(HTTPServerRequest request, ICrateSelector selector) {
    if("term" in request.query) {
      selector = selector.like("email", request.query["term"]);
    }

    return selector;
  }
}

/// it should search users by a term
unittest
{
  auto router = getTestRoute;
  userDataCrate.addItem(userJson.parseJsonString);

  request(router)
    .get("/users?term=john")
      .expectStatusCode(200)
      .end((Response response) => {
        response.bodyJson["users"].length.should.equal(0);
      });

  request(router)
    .get("/users?term=test")
      .expectStatusCode(200)
      .end((Response response) => {
        response.bodyJson["users"].length.should.equal(1);

        auto user = response.bodyJson["users"][0];
        user.keys.should.contain(["_id", "email", "name", "username"]);
        user.keys.should.not.contain(["isActive", "password", "salt", "scopes", "tokens"]);
        user["_id"].to!string.should.equal("1");
        user["email"].to!string.should.equal("test2@asd.asd");
        user["name"].to!string.should.equal("test");
        user["username"].to!string.should.equal("test_user");
      });
}