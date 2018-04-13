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
import std.range.interfaces;

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
  return new CrateRouter!RestApi(router);
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
    return this;
  }

  CrateRouter enableCrateAction(T: Crate!U, string actionName, U)(T crate)
  {
    return enableCrateAction!(T, actionName, RouterPolicy)(crate);
  }

  CrateRouter enableCrateAction(T: Crate!U, string actionName, Policy, U)(T crate)
  {
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

  CrateRouter add(T)(Crate!T crate, ICrateFilter[] filters ...)
  {
    return add!RouterPolicy(crate, filters);
  }

  CrateRouter add(Policy, Type)(Crate!Type crate, ICrateFilter[] filters ...)
  {
    router.putJsonWith!(Policy, Type)(&crate.updateItem);
    router.getWith!(Policy, Type)(&crate.getItem);
    router.getListFilteredWith!(Policy, Type)(&crate.getList, filters);

    return this;
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
          data["site"]["_id"] = "1";
          response.bodyJson.should.equal(data);
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
  }

  return &deserialize;
}

/// ditto
auto requestDeserializationHandler(U, T, V)(V delegate(T) @safe next) if(!is(V == void)) {
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

    auto result = next(value);
    response.statusCode = 200;
    response.writeJsonBody(serializer.denormalise(result.serializeToJson), U.mime);
  }

  return &deserialize;
}

/// ditto
auto requestDeserializedHandler(Policy, Type, V)(V delegate(Json) @safe next) {
  FieldDefinition definition = getFields!Type;
  auto serializer = new Policy.Serializer(definition);

  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @safe {
    string id;

    if("id" in request.params) {
      id = request.params["id"];
    }

    auto clientData = serializer.normalise(id, request.json);

    static if(is(V == void)) {
      next(clientData);
      response.statusCode = 204;
      response.writeVoidBody;
    } else {
      auto result = next(clientData);
      response.statusCode = 200;
      response.writeJsonBody(serializer.denormalise(result.serializeToJson), Policy.mime);
    }
  }

  return &deserialize;
}

/// Handle requests with id and without body
auto requestIdHandler(void delegate(string) @safe next) {

  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @safe {
    string id = request.params["id"];

    next(id);

    response.statusCode = 204;
    response.writeVoidBody;
  }

  return &deserialize;
}

/// ditto
auto requestIdHandler(void delegate(string, HTTPServerResponse) @safe next) {

  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @safe {
    string id = request.params["id"];

    next(id, response);
  }

  return &deserialize;
}

/// ditto
auto requestIdHandler(U, T)(T delegate(string) @safe next) if(!is(T == void)){
  FieldDefinition definition = getFields!T;
  auto serializer = new U.Serializer(definition);

  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @safe {
    string id = request.params["id"];

    Json jsonResponse;

    try {
      jsonResponse = serializer.denormalise(next(id).serializeToJson);
    } catch (JSONException e) {
      throw new CrateValidationException("Can not serialize data. " ~ e.msg, e.file, e.line);
    }

    response.writeJsonBody(jsonResponse, 200, U.mime);
  }

  return &deserialize;
}

/// Handle a request that returns a list of elements
auto requestListHandler(U, T)(T[] delegate() @safe next) if(!is(T == void)){
  FieldDefinition definition = getFields!T;
  auto serializer = new U.Serializer(definition);

  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @safe {
    Json jsonResponse;

    try {
      jsonResponse = serializer.denormalise(next().map!(a => a.serializeToJson).inputRangeObject);
    } catch (JSONException e) {
      throw new CrateValidationException("Can not serialize data. " ~ e.msg, e.file, e.line);
    }

    response.writeJsonBody(jsonResponse, 200, U.mime);
  }

  return &deserialize;
}


/// Handle a request that returns a list of elements before applying some filters
auto requestFilteredListHandler(U, T)(const ICrateSelector delegate(string[string]) @safe next, ICrateFilter[] filters...) if(!is(T == void)) {
  FieldDefinition definition = getFields!T;
  auto serializer = new U.Serializer(definition);

  ICrateFilter[] localFilters = filters.dup;

  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @trusted {
    Json jsonResponse;
    string[string] parameters;

    try {
      auto items = next(parameters);
      
      foreach(filter; localFilters) {
        items = filter.apply(request, items);
      }

      auto result = items.exec.array.inputRangeObject;
      jsonResponse = serializer.denormalise(result);
    } catch (JSONException e) {
      throw new CrateValidationException("Can not serialize data. " ~ e.msg, e.file, e.line);
    }

    response.writeJsonBody(jsonResponse, 200, U.mime);
  }

  return &deserialize;
}

///
URLRouter putJsonWith(Policy, Type, V)(URLRouter router, string route, V function(Json) @safe handler) {
  return putJsonWith!(Policy, Type)(router, route, handler.toDelegate);
}

/// ditto
URLRouter putJsonWith(Policy, Type, V)(URLRouter router, V delegate(Json) @safe handler) {
  FieldDefinition definition = getFields!Type;
  auto routing = new Policy.Routing(definition);

  return putJsonWith!(Policy, Type)(router, routing.put(), handler);
}

/// ditto
URLRouter putJsonWith(Policy, Type, V)(URLRouter router, V function(Json) @safe handler) {
  return putJsonWith!(Policy, Type)(router, handler.toDelegate);
}

/// ditto
URLRouter putJsonWith(Policy, Type, V)(URLRouter router, string route, V delegate(Json) @safe next) {
  enforce(route.endsWith("/:id"), "Invalid `" ~ route ~ "` route. It must end with `/:id`.");
  auto handler = requestDeserializedHandler!(Policy, Type)(next);

  return router.put(route, requestErrorHandler(handler));
}


/// Add a PUT route that parse the data according a Protocol
URLRouter putWith(Policy, T)(URLRouter router, string route, void function(T object, HTTPServerResponse res) @safe handler) {
  return putWith!(Policy, T)(router, route, handler.toDelegate);
}

/// ditto
URLRouter putWith(Policy, T, V)(URLRouter router, string route, V function(T object) @safe handler) {
  return putWith!(Policy)(router, route, handler.toDelegate);
}

/// ditto
URLRouter putWith(Policy, T, V)(URLRouter router, V function(T object) @safe handler) {
  return putWith!(Policy, T, V)(router, handler.toDelegate);
}

/// ditto
URLRouter putWith(Policy, T)(URLRouter router, void function(T object, HTTPServerResponse) @safe handler) {
  return putWith!(Policy, T)(router, handler.toDelegate);
}

/// ditto
URLRouter putWith(Policy, T, V)(URLRouter router, V delegate(T object) @safe handler) {
  FieldDefinition definition = getFields!T;
  auto routing = new Policy.Routing(definition);

  return putWith!(Policy, T, V)(router, routing.put(), handler);
}

/// ditto
URLRouter putWith(Policy, T)(URLRouter router, void delegate(T object, HTTPServerResponse) @safe handler) {
  FieldDefinition definition = getFields!T;
  auto routing = new Policy.Routing(definition);

  return putWith!(Policy, T)(router, routing.put(), handler.toDelegate);
}

/// ditto
URLRouter putWith(Policy, T)(URLRouter router, string route, void delegate(T object, HTTPServerResponse res) @safe handler) {
  enforce(route.endsWith("/:id"), "Invalid `" ~ route ~ "` route. It must end with `/:id`.");

  auto deserializationHandler = requestFullDeserializationHandler!(Policy, T)(handler);

  return router.put(route, requestErrorHandler(deserializationHandler));
}

/// ditto
URLRouter putWith(Policy, T, V)(URLRouter router, string route, V delegate(T object) @safe next) {
  enforce(route.endsWith("/:id"), "Invalid `" ~ route ~ "` route. It must end with `/:id`.");
  auto handler = requestDeserializationHandler!Policy(next);

  return router.put(route, requestErrorHandler(handler));
}



/// Add a POST route that parse the data according a Protocol
URLRouter postWith(Policy, T)(URLRouter router, string route, void function(T object, HTTPServerResponse res) @safe handler) {
  return postWith!(Policy, T)(router, route, handler.toDelegate);
}

/// ditto
URLRouter postWith(Policy, T)(URLRouter router, void function(T object, HTTPServerResponse res) @safe handler) {
  return postWith!(Policy, T)(router, handler.toDelegate);
}

/// ditto
URLRouter postWith(Policy, T, V)(URLRouter router, V function(T object) @safe handler) {
  return postWith!(Policy, T, V)(router, handler.toDelegate);
}

/// ditto
URLRouter postWith(Policy, T, V)(URLRouter router, string route, V function(T object) @safe handler) {
  return postWith!(Policy, T, V)(router, route, handler.toDelegate);
}

/// ditto
URLRouter postWith(Policy, T)(URLRouter router, string route, void delegate(T object, HTTPServerResponse res) @safe handler) {
  auto deserializationHandler = requestFullDeserializationHandler!(Policy, T)(handler);

  return router.post(route, requestErrorHandler(deserializationHandler));
}

/// ditto
URLRouter postWith(Policy, T)(URLRouter router, void delegate(T object, HTTPServerResponse res) @safe handler) {
  FieldDefinition definition = getFields!T;
  auto routing = new Policy.Routing(definition);

  return postWith!(Policy, T)(router, routing.post, handler);
}

/// ditto
URLRouter postWith(Policy, T, V)(URLRouter router, V delegate(T object) @safe handler) {
  FieldDefinition definition = getFields!T;
  auto routing = new Policy.Routing(definition);

  return postWith!(Policy, T, V)(router, routing.post, handler);
}

/// ditto
URLRouter postWith(Policy, T, V)(URLRouter router, string route, V delegate(T object) @safe handler) {
  auto deserializationHandler = requestDeserializationHandler!(Policy, T, V)(handler);

  return router.post(route, requestErrorHandler(deserializationHandler));
}




/// Add a DELETE route that parse the data according a Protocol
URLRouter deleteWith(Policy)(URLRouter router, string route, void function(string id, HTTPServerResponse res) @safe handler) {
  return deleteWith!(Policy)(router, route, handler.toDelegate);
}

URLRouter deleteWith(Policy, T)(URLRouter router, void function(string id, HTTPServerResponse res) @safe handler) {
  return deleteWith!(Policy, T)(router, handler.toDelegate);
}

/// ditto
URLRouter deleteWith(Policy)(URLRouter router, string route, void function(string id) @safe handler) {
  return deleteWith!Policy(router, route, handler.toDelegate);
}


/// ditto
URLRouter deleteWith(Policy, T)(URLRouter router, void function(string id) @safe handler) {
  return deleteWith!(Policy, T)(router, handler.toDelegate);
}

/// ditto
URLRouter deleteWith(Policy)(URLRouter router, string route, void delegate(string id, HTTPServerResponse res) @safe handler) {
  enforce(route.endsWith("/:id"), "Invalid `" ~ route ~ "` route. It must end with `/:id`.");
  auto idHandler = requestIdHandler(handler);

  return router.delete_(route, requestErrorHandler(idHandler));
}

/// ditto
URLRouter deleteWith(Policy, T)(URLRouter router, void delegate(string id, HTTPServerResponse res) @safe handler) {
  FieldDefinition definition = getFields!T;
  auto routing = new Policy.Routing(definition);

  return deleteWith!(Policy)(router, routing.delete_, handler);
}

/// ditto
URLRouter deleteWith(Policy, T)(URLRouter router, void delegate(string id) @safe handler) {
  FieldDefinition definition = getFields!T;
  auto routing = new Policy.Routing(definition);

  return deleteWith!(Policy)(router, routing.delete_, handler);
}

/// ditto
URLRouter deleteWith(Policy)(URLRouter router, string route, void delegate(string id) @safe handler) {
  enforce(route.endsWith("/:id"), "Invalid `" ~ route ~ "` route. It must end with `/:id`.");
  auto idHandler = requestIdHandler(handler);

  return router.delete_(route, requestErrorHandler(idHandler));
}



/// add a GET route that returns to the client one item selected by id
URLRouter getWith(Policy, T)(URLRouter router, string route, T function(string id) @safe handler) if(!is(T == void)) {
  return getWith!(Policy, T)(router, route, handler.toDelegate);
}

/// ditto
URLRouter getWith(Policy)(URLRouter router, string route, void function(string id, HTTPServerResponse res) @safe handler) if(!is(T == void)) {
  return getWith!(Policy)(router, route, handler.toDelegate);
}

/// ditto
URLRouter getWith(Policy, T)(URLRouter router, void function(string id, HTTPServerResponse res) @safe handler) if(!is(T == void)) {
  return getWith!(Policy, T)(router, handler.toDelegate);
}

/// ditto
URLRouter getWith(Policy, T)(URLRouter router, T function(string id) @safe handler) if(!is(T == void)) {
  return getWith!(Policy, T)(router, handler.toDelegate);
}

/// ditto
URLRouter getWith(Policy, T)(URLRouter router, string route, T delegate(string id) @safe handler) if(!is(T == void)) {
  enforce(route.endsWith("/:id"), "Invalid `" ~ route ~ "` route. It must end with `/:id`.");
  auto idHandler = requestIdHandler!(Policy, T)(handler);

  return router.get(route, requestErrorHandler(idHandler));
}

/// ditto
URLRouter getWith(Policy)(URLRouter router, string route, void delegate(string id, HTTPServerResponse res) @safe handler) if(!is(T == void)) {
  enforce(route.endsWith("/:id"), "Invalid `" ~ route ~ "` route. It must end with `/:id`.");
  auto idHandler = requestIdHandler(handler);

  return router.get(route, requestErrorHandler(idHandler));
}

/// ditto
URLRouter getWith(Policy, T)(URLRouter router, T delegate(string id) @safe handler) if(!is(T == void)) {
  FieldDefinition definition = getFields!T;
  auto routing = new Policy.Routing(definition);

  return getWith!(Policy, T)(router, routing.get, handler);
}

/// ditto
URLRouter getWith(Policy, Type)(URLRouter router, ICrateSelector delegate(string id) @safe handler) if(!is(T == void)) {
  Type resultExtractor(string id) @trusted {
    return handler(id).exec.front.deserializeJson!Type;
  }

  return getWith!(Policy, Type)(router, &resultExtractor);
}

/// ditto
URLRouter getWith(Policy, T)(URLRouter router, void delegate(string id, HTTPServerResponse res) @safe handler) if(!is(T == void)) {
  FieldDefinition definition = getFields!T;
  auto routing = new Policy.Routing(definition);

  return getWith!(Policy)(router, routing.get, handler);
}


/// GET All
URLRouter getListWith(Policy, T)(URLRouter router, string route, T[] function() @safe handler) if(!is(T == void)) {
  return getListWith!(Policy, T)(router, route, handler.toDelegate);
}

/// ditto
URLRouter getListWith(Policy, T)(URLRouter router, T[] function() @safe handler) if(!is(T == void)) {
  return getListWith!(Policy, T)(router, handler.toDelegate);
}

/// ditto
URLRouter getListWith(Policy, T)(URLRouter router, string route, T[] delegate() @safe handler) if(!is(T == void)) {
  auto listHandler = requestListHandler!(Policy, T)(handler);

  return router.get(route, requestErrorHandler(listHandler));
}

/// ditto
URLRouter getListWith(Policy, T)(URLRouter router, T[] delegate() @safe handler) if(!is(T == void)) {
  FieldDefinition definition = getFields!T;
  auto routing = new Policy.Routing(definition);

  return getListWith!(Policy, T)(router, routing.getList, handler.toDelegate);
}

/// ditto
URLRouter getListFilteredWith(Policy, Type)(URLRouter router, ICrateSelector delegate(string[string]) @safe handler, ICrateFilter[] filters ...) {
  FieldDefinition definition = getFields!Type;
  auto routing = new Policy.Routing(definition);

  import std.stdio;

  auto listHandler = requestFilteredListHandler!(Policy, Type)(handler, filters);

  return router.get(routing.getList, requestErrorHandler(listHandler));
}
