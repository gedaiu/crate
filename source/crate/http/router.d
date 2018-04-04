module crate.http.router;

import crate.error;
import crate.base;
import crate.ctfe;
import crate.collection.proxy;
import crate.http.methodcollection;
import crate.http.action.model;
import crate.http.action.crate;

import crate.http.resource;

import crate.policy.jsonapi;
import crate.policy.restapi;

import vibe.data.json;
import vibe.http.router;

import std.conv;
import std.traits;
import std.stdio;
import std.functional;
import std.exception;

alias DefaultPolicy = crate.policy.restapi.CrateRestApiPolicy;

string basePath(T)(string name, const CrateConfig!T config)
{
  static if (isAggregateType!T || is(T == void))
  {
    if (name == "Json API")
    {
      return crate.policy.jsonapi.basePath(config);
    }

    if (name == "Rest API")
    {
      return crate.policy.restapi.basePath(config);
    }
  }

  assert(false, "Unknown policy `" ~ name ~ "`");
}

auto crateSetup(T)(URLRouter router) {
  return new CrateRouter!T(router);
}

auto crateSetup(URLRouter router) {
  return new CrateRouter!CrateRestApiPolicy(router);
}

private static CrateCollection[URLRouter] proxyCollection;

class CrateRouter(RouterPolicy) {

  private
  {
    URLRouter router;
    CrateRoutes definedRoutes;

    bool[string] mimeList;
  }

  this(URLRouter router)
  {
    this.router = router;

    if(router !in proxyCollection) {
      proxyCollection[router] = new CrateCollection();
    }
  }

  CrateRouter enableResource(T, string resourcePath)()
  {
    return enableResource!(T, resourcePath, RouterPolicy);
  }

  CrateRouter enableResource(T, string resourcePath, Policy)()
  {
    auto const policy = new Policy;
    auto config = proxyCollection[router].getByType(T.stringof).config;

    auto path = basePath(policy.name, config) ~ "/:id/" ~ resourcePath;
    auto resource = new Resource!(T, resourcePath)(proxyCollection[router]);

    router.get(path, checkError(policy, &resource.get));
    router.post(path, checkError(policy, &resource.post));

    return this;
  }

  CrateRouter dataTransformer(T)(T user) {
    return this;
  }

  CrateRouter enableAction(T: Crate!U, string actionName, U)()
  {
    return enableAction!(T, actionName, RouterPolicy);
  }

  CrateRouter enableAction(T: Crate!U, string actionName, Policy, U)()
  {
    auto const policy = new Policy;
    auto action = new ModelAction!(T, actionName)(proxyCollection[router]);
    auto config = proxyCollection[router].getByType(U.stringof).config;
    auto path = basePath(policy.name, config) ~ "/:id/" ~ actionName;

    definedRoutes.paths[path][action.method][200] = PathDefinition(action.returnType, "", CrateOperation.otherItem);

    router.match(action.method, path, checkError(policy, &action.handler));

    return this;
  }

  CrateRouter enableCrateAction(T: Crate!U, string actionName, U)(T crate)
  {
    return enableCrateAction!(T, actionName, RouterPolicy)(crate);
  }

  CrateRouter enableCrateAction(T: Crate!U, string actionName, Policy, U)(T crate)
  {
    auto const policy = new Policy;
    auto action = new CrateAction!(T, actionName)(crate);
    auto config = proxyCollection[router].getByType(U.stringof).config;
    auto path = basePath(policy.name, config) ~ "/:id/" ~ actionName;

    definedRoutes.paths[path][action.method][200] = PathDefinition(action.returnType, "", CrateOperation.otherItem);

    router.match(action.method, path, checkError(policy, &action.handler));

    return this;
  }

  CrateRoutes allRoutes()
  {
    return definedRoutes;
  }

  string[] mime()
  {
    return mimeList.keys;
  }

  CrateRouter add(Policy, T)(Crate!T crate, ICrateFilter[] filters ...)
  {
    const policy = new const Policy;

    mimeList[policy.mime] = true;

    auto tmpRoutes = defineRoutes!T(policy, crate.config());

    foreach (string name, schema; tmpRoutes.schemas)
    {
      definedRoutes.schemas[name] = schema;
    }

    foreach (string path, methods; tmpRoutes.paths)
    {
      foreach (method, responses; methods)
      {
        foreach (response, pathDefinition; responses)
        {
          definedRoutes.paths[path][method][response] = pathDefinition;
        }
      }
    }

    bindRoutes(tmpRoutes, policy, crate, filters);

    proxyCollection[router].addByPath(basePath(policy.name, crate.config), crate);

    return this;
  }

  CrateRouter add(T)(Crate!T crate, ICrateFilter[] filters ...)
  {
    return add!RouterPolicy(crate, filters);
  }

  private
  {
    void bindRoutes(T)(CrateRoutes routes, const CratePolicy policy, Crate!T crate, ICrateFilter[] filters)
    {
      auto methodCollection = new MethodCollection!T(policy, proxyCollection[router], crate.config, filters);

      if (crate.config.getList || crate.config.addItem)
      {
        router.match(HTTPMethod.OPTIONS, basePath(policy.name, crate.config),
            checkError(policy, &methodCollection.optionsList));
      }

      if (crate.config.getItem || crate.config.updateItem || crate.config.deleteItem)
      {
        router.match(HTTPMethod.OPTIONS, basePath(policy.name, crate.config) ~ "/:id",
            checkError(policy, &methodCollection.optionsItem));
      }

      foreach (string path, methods; routes.paths)
        foreach (method, responses; methods)
          foreach (response, pathDefinition; responses) {
            addRoute(policy, path, methodCollection, pathDefinition);
          }
    }

    void addRoute(T)(const CratePolicy policy, string path, MethodCollection!T methodCollection, PathDefinition definition)
    {
      switch (definition.operation)
      {
      case CrateOperation.getList:
        router.get(path, checkError(policy, &methodCollection.getList));
        break;

      case CrateOperation.getItem:
        router.get(path, checkError(policy, &methodCollection.getItem));
        break;

      case CrateOperation.addItem:
        router.post(path, checkError(policy, &methodCollection.postItem));
        break;

      case CrateOperation.deleteItem:
        router.delete_(path,
            checkError(policy, &methodCollection.deleteItem));
        break;

      case CrateOperation.updateItem:
        router.patch(path,
            checkError(policy, &methodCollection.updateItem));
        break;

      case CrateOperation.replaceItem:
        router.put(path,
            checkError(policy, &methodCollection.replaceItem));
        break;

      default:
        throw new Exception("Operation not supported: " ~ definition.operation.to!string);
      }
    }

    auto checkError(T)(const CratePolicy policy, T func)
    {
      void check(HTTPServerRequest request, HTTPServerResponse response)
      {
        try
        {
          func(request, response);
        }
        catch (Exception e)
        {
          Json data = e.toJson;
          version(unittest) {} else debug stderr.writeln(e);
          response.writeJsonBody(data, data["errors"][0]["status"].to!int, policy.mime);
        }
      }

      return &check;
    }
  }
}

auto requestErrorHandler(void function(HTTPServerRequest, HTTPServerResponse) @safe next) {
  return requestErrorHandler(next.toDelegate);
}

auto requestErrorHandler(void delegate(HTTPServerRequest, HTTPServerResponse) @safe next) {
  void check(HTTPServerRequest request, HTTPServerResponse response) @safe {
    try {
      next(request, response);
    } catch(CrateException e) {
      response.writeJsonBody(e.toJson, e.statusCode);
    } catch (Exception e) {
      Json data = e.toJson;
      version(unittest) {} else debug stderr.writeln(e);
      response.writeJsonBody(data, data["errors"][0]["status"].to!int);
    }
  }
  
  return &check;
}

version (unittest)
{
  import crate.base;
  import fluentasserts.vibe.request;
  import fluentasserts.vibe.json;
  import vibe.data.json;
  import vibe.data.bson;
  import crate.collection.memory;
  import std.algorithm;
  import std.array;
  import fluent.asserts;

  struct TestModel
  {
    @optional string _id = "1";
    string name = "";

    void actionChange()
    {
      name = "changed";
    }

    void actionParam(string data)
    {
      name = data;
    }
  }

  class TestCrate(T) : MemoryCrate!T
  {
    void action() {}

    override
    ICrateSelector getList(string[string] parameters) {

      if("type" in parameters) {
        return new CrateRange(super.getList(parameters).exec
          .filter!(a => a["position"]["type"].to!string == parameters["type"]));
      }

      return super.getList(parameters);
    }
  }

  struct Point
  {
    string type = "Point";
    float[2] coordinates;
  }

  struct Site
  {
    string _id = "1";
    Point position;

    Json toJson() const @safe {
      Json data = Json.emptyObject;

      data["_id"] = _id;
      data["position"] = position.serializeToJson;

      return data;
    }

    static Site fromJson(Json src) @safe {
      return Site(
        src["_id"].to!string,
        Point("Point", [ src["position"]["coordinates"][0].to!int, src["position"]["coordinates"][1].to!int ])
      );
    }
  }
}

@("REST API query test")
unittest
{
  auto router = new URLRouter();
  auto baseCrate = new TestCrate!Site;

  router
    .crateSetup
      .add(baseCrate);

  Json data1 = `{
      "position": {
        "type": "Point",
        "coordinates": [0, 0]
      }
  }`.parseJsonString;

  Json data2 = `{
      "position": {
        "type": "Dot",
        "coordinates": [1, 1]
      }
  }`.parseJsonString;

  baseCrate.addItem(data1);
  baseCrate.addItem(data2);

  request(router)
    .get("/sites?type=Point")
      .expectStatusCode(200)
      .end((Response response) => {
        response.bodyJson["sites"].length.should.equal(1);
        response.bodyJson["sites"][0]["_id"].to!string.should.equal("1");
      });
}

version(unittest) {
  import crate.policy.restapi;
  import std.stdio;

  auto testRouter() {
    auto router = new URLRouter();
    auto baseCrate = new TestCrate!Site;

    router
      .crateSetup
        .add(baseCrate)
          .enableCrateAction!(TestCrate!Site, "action")(baseCrate);

    Json data = `{
        "position": {
          "type": "Point",
          "coordinates": [0, 0]
        }
    }`.parseJsonString;

    baseCrate.addItem(data);

    return request(router);
  }
}

@("GET all items using REST API")
unittest
{
  testRouter
    .get("/sites")
      .expectStatusCode(200)
      .end((Response response) => {
        response.bodyJson["sites"].length.should.be.greaterThan(0);
        response.bodyJson["sites"][0]["_id"].to!string.should.equal("1");
      });
}

@("GET one item using REST API")
unittest
{
  testRouter
    .get("/sites/1")
      .expectStatusCode(200)
      .end((Response response) => {
        response.bodyJson.keys.should.equal(["site"]);
        response.bodyJson["site"].keys.should.contain(["position", "_id"]);
        response.bodyJson["site"]["_id"].to!string.should.equal("1");
      });
}

@("POST invalid item using REST API")
unittest
{
  auto data = `{
    "site": {
      "latitude": "0",
      "longitude": "0"
    }
  }`.parseJsonString;

  testRouter
    .post("/sites")
      .send(data)
        .expectStatusCode(400)
        .end((Response response) => {
          response.bodyJson["errors"][0]["title"].to!string.should.equal("Validation error");
        });
}

@("POST valid item using REST API")
unittest
{
  auto data = `{
    "site": {
      "position": {
        "type": "Point",
        "coordinates": [23, 21]
      }
    }
  }`.parseJsonString;

  testRouter
    .post("/sites")
      .send(data)
        .expectStatusCode(201)
        .end((Response response) => {
          response.bodyJson["site"]["_id"].to!string.should.equal("2");
        });
}

@("PUT one item using REST API")
unittest
{
  auto data = `{
    "site": {
      "position": {
        "type": "Point",
        "coordinates": [0, 1]
      }
    }
  }`.parseJsonString;

  testRouter
    .put("/sites/1")
      .send(data)
        .expectStatusCode(200)
        .end((Response response) => {
          response.bodyJson["site"]["position"]["coordinates"][0].to!int.should.equal(0);
          response.bodyJson["site"]["position"]["coordinates"][1].to!int.should.equal(1);
        });
}

@("DELETE one item using REST API")
unittest
{
  testRouter
    .delete_("/sites/1")
      .expectStatusCode(204)
      .end();
}

version(unittest) {
  class SomeTestCrateFilter : ICrateFilter {
    ICrateSelector apply(HTTPServerRequest request, ICrateSelector selector) {
      return new CrateRange(selector.exec.filter!(a => a["position"]["type"] == "Point"));
    }
  }

  auto queryRouter() {
    auto router = new URLRouter();
    auto baseCrate = new MemoryCrate!Site;

    router
      .crateSetup
        .add(baseCrate, new SomeTestCrateFilter);

    Json data1 = `{
        "position": {
          "type": "Point",
          "coordinates": [0, 0]
        }
    }`.parseJsonString;

    Json data2 = `{
        "position": {
          "type": "Dot",
          "coordinates": [1, 1]
        }
    }`.parseJsonString;

    baseCrate.addItem(data1);
    baseCrate.addItem(data2);

    return router;
  }
}

@("Request all items using query alteration")
unittest {
  request(queryRouter)
    .get("/sites")
      .expectStatusCode(200)
      .end((Response response) => {
        response.bodyJson["sites"].length.should.equal(1);
      });
}

@("Get available items with query alteration")
unittest {
  request(queryRouter)
    .get("/sites/1")
      .expectStatusCode(200)
      .end((Response response) => {
        response.bodyJson["site"]["_id"].to!string.should.equal("1");
      });
}

@("Get unavailable items with query alteration")
unittest {
  request(queryRouter)
    .get("/sites/2")
      .expectStatusCode(404)
      .end();
}

@("Replace available items using query alteration")
unittest {
  Json dataUpdate = `{ "site": {
      "position": {
        "type": "Point",
        "coordinates": [0, 0]
      }
  }}`.parseJsonString;

  request(queryRouter)
    .put("/sites/1")
      .send(dataUpdate)
        .expectStatusCode(200)
        .end();
}

@("Replace available items using query alteration")
unittest {
  Json dataUpdate = `{ "site": {
      "position": {
        "type": "Point",
        "coordinates": [0, 0]
      }
  }}`.parseJsonString;

  request(queryRouter)
    .put("/sites/2")
      .send(dataUpdate)
        .expectStatusCode(404)
        .end();
}

@("Delete available items using query alteration")
unittest {
  request(queryRouter)
    .delete_("/sites/1")
      .expectStatusCode(204)
      .end();
}

@("Delete unavailable items using query alteration")
unittest {
  request(queryRouter)
    .delete_("/sites/2")
        .expectStatusCode(404)
        .end();
}

//// 
import crate.serializer.restapi;
import crate.serializer.jsonapi;

/// Call the next handler after the request data is deserialized
auto requestFullDeserializationHandler(U, T, V)(V delegate(T, HTTPServerResponse) @safe next) {
  FieldDefinition definition = getFields!T;
  auto serializer = new U.Serializer(definition);

  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @safe {
    string id;

    if("id" in request.params) {
      id = request.params["id"];
    }

    auto clientData = serializer.normalise(id, request.json);
    T value;

    try {
      value = clientData.deserializeJson!T;
    } catch (JSONException e) {
      throw new CrateValidationException("Can not deserialize data. " ~ e.msg, e.file, e.line);
    }

    static if(is(V == void)) {
      next(value, response);
      response.statusCode = 204;
      response.writeVoidBody;
    } else {
      auto result = next(value, response);
      response.statusCode = 200;
      response.writeJsonBody(serializer.denormalise(result.serializeToJson), U.mime);
    }
  }

  return &deserialize;
}

/// ditto
auto requestFullDeserializationHandler(U, T)(void delegate(T, HTTPServerResponse) @safe next) {
  FieldDefinition definition = getFields!T;
  auto serializer = new U.Serializer(definition);

  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @safe {
    string id;

    if("id" in request.params) {
      id = request.params["id"];
    }

    auto clientData = serializer.normalise(id, request.json);
    T value;

    try {
      value = clientData.deserializeJson!T;
    } catch (JSONException e) {
      throw new CrateValidationException("Can not deserialize data. " ~ e.msg, e.file, e.line);
    }

    next(value, response);

    response.statusCode = 204;
    response.writeVoidBody;
  }

  return &deserialize;
}

/// Add a PUT route that parse the data according a Protocol
URLRouter putWith(U, T, V)(URLRouter router, string route, V function(T object, HTTPServerResponse res) @safe handler) {
  return putWith!(U, T, V)(router, route, handler.toDelegate);
}

/// ditto
URLRouter putWith(U, T, V)(URLRouter router, string route, V delegate(T object, HTTPServerResponse res) @safe handler) {
  enforce(route.endsWith("/:id"), "Invalid `" ~ route ~ "` route. It must end with `/:id`.");

  auto deserializationHandler = requestFullDeserializationHandler!(U, T, V)(handler);

  return router.put(route, requestErrorHandler(deserializationHandler));
}

/// Add a POST route that parse the data according a Protocol
URLRouter postWith(U, T, V)(URLRouter router, string route, V function(T object, HTTPServerResponse res) @safe handler) {
  return postWith!(U, T, V)(router, route, handler.toDelegate);
}


/// ditto
URLRouter postWith(U, T, V)(URLRouter router, string route, V delegate(T object, HTTPServerResponse res) @safe handler) {
  auto deserializationHandler = requestFullDeserializationHandler!(U, T, V)(handler);

  return router.post(route, requestErrorHandler(deserializationHandler));
}
