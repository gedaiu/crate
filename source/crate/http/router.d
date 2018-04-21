module crate.http.router;

import crate.error;
import crate.base;
import crate.ctfe;
import crate.collection.proxy;
import crate.http.methodcollection;
import crate.http.action.model;
import crate.http.action.crate;
import crate.generator.openapi;

import crate.http.resource;

import crate.policy.jsonapi;
import crate.policy.restapi;

import vibe.data.json;
import vibe.http.router;
import vibe.stream.operations;

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

  CrateRouter enableResource(Type, string resourcePath)(Crate!Type crate)
  {
    router.getResource!(RouterPolicy, Type, resourcePath)(&crate.getItem);
    router.setResource!(RouterPolicy, Type, resourcePath)(&crate.getItem, &crate.updateItem);

    return this;
  }

  CrateRouter dataTransformer(T)(T user) {
    return this;
  }

  CrateRouter enableAction(Type, string actionName)(Crate!Type crate) {
    return enableAction!(RouterPolicy, Type, actionName)(crate);
  }

  CrateRouter enableAction(Policy, Type, string actionName)(Crate!Type crate) {
    router.enableAction!(Policy, Type, actionName)(&crate.getItem, &crate.updateItem);
  
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
    router.postJsonWith!(Policy, Type)(&crate.addItem);
    router.patchJsonWith!(Policy, Type)(&crate.updateItem, &crate.getItem);
    router.deleteWith!(Policy, Type)(&crate.deleteItem);
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

  class TypeFilter : ICrateFilter {
    ICrateSelector apply(HTTPServerRequest request, ICrateSelector selector) {
      if("type" !in request.query) {
        return selector;
      }

      return selector.where("position.type", request.query["type"]);
    }
  }

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
  auto baseCrate = new MemoryCrate!Site;

  router
    .crateSetup
      .add(baseCrate, new TypeFilter);

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
    auto baseCrate = new MemoryCrate!Site;

    router
      .crateSetup
        .add(baseCrate);

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

  auto expected = "{
    \"errors\": [{ 
      \"description\": \"Missing `position` value.\", 
      \"title\": \"Validation error\", 
      \"status\": 400
    }]
  }".parseJsonString;

  testRouter
    .post("/sites")
      .send(data)
        .expectStatusCode(400)
        .end((Response response) => {
          response.bodyJson.should.equal(expected);
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
    .get("/sites/22")
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

/// Replace a missing resource
unittest {
  Json dataUpdate = `{ "site": {
      "position": {
        "type": "Point",
        "coordinates": [0, 0]
      }
  }}`.parseJsonString;

  request(queryRouter)
    .put("/sites/24")
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

/// Delete unavailable items using query alteration
unittest {
  request(queryRouter)
    .delete_("/sites/24")
        .expectStatusCode(404)
        .end();
}

//// 
import crate.serializer.restapi;
import crate.serializer.jsonapi;

/// Call the next handler after the request data is deserialized
auto requestFullDeserializationHandler(U, T)(void delegate(T, HTTPServerResponse) @safe next, CrateRule rule) {
  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @safe {
    string id;

    if("id" in request.params) {
      id = request.params["id"];
    }

    auto clientData = rule.request.serializer.normalise(id, request.json);
    T value;

    try {
      value = clientData.deserializeJson!T;
    } catch (JSONException e) {
      throw new CrateValidationException("Can not deserialize data. " ~ e.msg, e.file, e.line);
    }

    response.statusCode = rule.response.statusCode;

    next(value, response);
  }

  return &deserialize;
}

/// ditto
auto requestDeserializationHandler(U, T, V)(V delegate(T) @safe next, CrateRule rule) if(!is(V == void)) {
  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @safe {
    string id;

    if("id" in request.params) {
      id = request.params["id"];
    }

    auto clientData = rule.request.serializer.normalise(id, request.json);
    T value;

    try {
      value = clientData.deserializeJson!T;
    } catch (JSONException e) {
      throw new CrateValidationException("Can not deserialize data. " ~ e.msg, e.file, e.line);
    }

    auto result = next(value);
    response.statusCode = rule.response.statusCode;
    response.writeJsonBody(rule.response.serializer.denormalise(result.serializeToJson), U.mime);
  }

  return &deserialize;
}

/// ditto
auto requestDeserializedHandler(Policy, Type, V)(V delegate(Json) @safe setItem, CrateRule rule) {

  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @safe {
    string id;

    if("id" in request.params) {
      id = request.params["id"];
    }

    auto clientData = rule.request.serializer.normalise(id, request.json);

    static if(is(V == void)) {
      setItem(clientData);
      response.statusCode = 204;
      response.writeVoidBody;
    } else static if(is(V == Json)) {
      auto result = setItem(clientData);
      response.statusCode = rule.response.statusCode;
      response.writeJsonBody(rule.response.serializer.denormalise(result), Policy.mime);
    } else {
      auto result = setItem(clientData);
      response.statusCode = rule.response.statusCode;
      response.writeJsonBody(rule.response.serializer.denormalise(result.serializeToJson), Policy.mime);
    }
  }

  return &deserialize;
}

/// ditto
auto requestDeserializedHandler(Policy, Type, V, U)(V delegate(Json) @safe setItem, U delegate(string) @safe getItem, CrateRule rule) {

  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @trusted {
    string id;

    id = request.params["id"];

    Json oldData = getItem(id).exec.front;
    auto clientData = mix(oldData, rule.request.serializer.normalise(id, request.json));

    static if(is(V == void)) {
      setItem(clientData);
      response.statusCode = 204;
      response.writeVoidBody;
    } else static if(is(V == Json)) {
      auto result = setItem(clientData);
      response.statusCode = rule.response.statusCode;
      response.writeJsonBody(rule.response.serializer.denormalise(result), Policy.mime);
    } else {
      auto result = setItem(clientData);
      response.statusCode = rule.response.statusCode;
      response.writeJsonBody(rule.response.serializer.denormalise(result.serializeToJson), Policy.mime);
    }
  }

  return &deserialize;
}

/// Handle requests with id and without body
auto requestIdHandler(void delegate(string) @safe next, CrateRule rule) {

  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @safe {
    string id = request.params["id"];

    next(id);

    response.statusCode = rule.response.statusCode;
    response.writeVoidBody;
  }

  return &deserialize;
}

/// ditto
auto requestIdHandler(void delegate(string, HTTPServerResponse) @safe next, CrateRule rule) {

  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @safe {
    string id = request.params["id"];
    response.statusCode = rule.response.statusCode;
    next(id, response);
  }

  return &deserialize;
}

/// ditto
auto requestIdHandler(T)(T delegate(string) @safe next, CrateRule rule) if(!is(T == void)){
  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @safe {
    string id = request.params["id"];

    Json jsonResponse;

    try {
      jsonResponse = rule.response.serializer.denormalise(next(id).serializeToJson);
    } catch (JSONException e) {
      throw new CrateValidationException("Can not serialize data. " ~ e.msg, e.file, e.line);
    }

    response.writeJsonBody(jsonResponse, 200, rule.response.mime);
  }

  return &deserialize;
}

/// Handle a request that returns a list of elements
auto requestListHandler(U, T)(T[] delegate() @safe next) if(!is(T == void)) {
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
auto requestFilteredListHandler(U, T)(const ICrateSelector delegate() @safe next, ICrateFilter[] filters...) if(!is(T == void)) {
  FieldDefinition definition = getFields!T;
  auto serializer = new U.Serializer(definition);

  ICrateFilter[] localFilters = filters.dup;

  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @trusted {
    Json jsonResponse;

    try {
      auto items = next();

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

auto requestActionHandler(Type, string actionName, T, U, V)(T delegate(string id) @system getElement, U delegate(V item) @system updateElement, CrateRule rule) 
    if(is(T == ICrateSelector) || is(T == Json) || is(T == Type)) {
  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @trusted {
    string id = request.params["id"];

    auto queryValue = getElement(id);

    static if(is(T == ICrateSelector)) {
      auto result = queryValue.exec;
      enforce!CrateNotFoundException(!result.empty, "Missing `" ~ Type.stringof ~ "`.");

      Type value = result.front.deserializeJson!Type;
    } else static if(is(T == Json)) {
      Type value = queryValue.deserializeJson!Type;
    } else {
      alias value = queryValue;
    }

    alias Func = typeof(__traits(getMember, value, actionName));
    
    static if(Parameters!Func.length == 0) {
      alias Param = void;
    } else {
      alias Param = Parameters!Func[0];
    }

    static if(is(ReturnType!Func == void)) {
      static if(is(Param == void)) {
        __traits(getMember, value, actionName)();
      } else {
        __traits(getMember, value, actionName)(request.bodyReader.readAllUTF8.to!Param);
      }

      static if(is(V == Json)) {
        updateElement(value.serializeToJson);
      } else {
        updateElement(value);
      }

      response.statusCode = rule.response.statusCode;
      
      response.writeVoidBody();
    } else {

      static if(is(Param == void)) {
        auto output = __traits(getMember, value, actionName)();
      } else {
        auto output = __traits(getMember, value, actionName)(request.bodyReader.readAllUTF8.to!Param);
      }

      static if(is(V == Json)) {
        updateElement(value.serializeToJson);
      } else {
        updateElement(value);
      }

      response.writeBody(output, rule.response.statusCode, rule.response.mime);
    }
  }

  return &deserialize;
}

///
URLRouter putJsonWith(Policy, Type, V)(URLRouter router, V function(Json) @safe handler) {
  return putJsonWith!(Policy, Type)(router, handler.toDelegate);
}

/// ditto
URLRouter putJsonWith(Policy, Type, V)(URLRouter router, V delegate(Json) @safe next) {
  FieldDefinition definition = getFields!Type;
  auto rule = Policy.replace(definition);

  enforce(rule.request.path.endsWith("/:id"), "Invalid `" ~ rule.request.path ~ "` route. It must end with `/:id`.");

  auto handler = requestDeserializedHandler!(Policy, Type)(next, rule);

  return router.put(rule.request.path, requestErrorHandler(handler));
}

/// Add a PUT route that parse the data according a Protocol
URLRouter putWith(Policy, T, V)(URLRouter router, V function(T object) @safe handler) {
  return putWith!(Policy, T, V)(router, handler.toDelegate);
}

/// ditto
URLRouter putWith(Policy, T)(URLRouter router, void function(T object, HTTPServerResponse) @safe handler) {
  return putWith!(Policy, T)(router, handler.toDelegate);
}

/// ditto
URLRouter putWith(Policy, Type)(URLRouter router, void delegate(Type object, HTTPServerResponse res) @safe handler) {
  FieldDefinition definition = getFields!Type;
  auto rule = Policy.replace(definition);

  enforce(rule.request.path.endsWith("/:id"), "Invalid `" ~ rule.request.path ~ "` route. It must end with `/:id`.");

  auto deserializationHandler = requestFullDeserializationHandler!(Policy, Type)(handler, rule);

  return router.put(rule.request.path, requestErrorHandler(deserializationHandler));
}

/// ditto
URLRouter putWith(Policy, Type, V)(URLRouter router, V delegate(Type object) @safe next) {
  FieldDefinition definition = getFields!Type;
  auto rule = Policy.replace(definition);

  enforce(rule.request.path.endsWith("/:id"), "Invalid `" ~ rule.request.path ~ "` route. It must end with `/:id`.");
  auto handler = requestDeserializationHandler!Policy(next, rule);

  return router.put(rule.request.path, requestErrorHandler(handler));
}

///
URLRouter patchJsonWith(Policy, Type, V, U)(URLRouter router, V function(Json) @safe setItem, U function(string) @safe getItem) {
  return patchJsonWith!(Policy, Type)(router, setItem.toDelegate);
}

/// ditto
URLRouter patchJsonWith(Policy, Type, V, U)(URLRouter router, V delegate(Json) @safe setItem, U delegate(string) @safe getItem) {
  FieldDefinition definition = getFields!Type;
  auto rule = Policy.patch(definition);

  enforce(rule.request.path.endsWith("/:id"), "Invalid `" ~ rule.request.path ~ "` route. It must end with `/:id`.");

  auto handler = requestDeserializedHandler!(Policy, Type)(setItem, getItem, rule);

  return router.addRule(rule, requestErrorHandler(handler));
}








/// Add a POST route that parse the data according a Protocol
URLRouter postWith(Policy, T)(URLRouter router, void function(T object, HTTPServerResponse res) @safe handler) {
  return postWith!(Policy, T)(router, handler.toDelegate);
}

/// ditto
URLRouter postWith(Policy, T, V)(URLRouter router, V function(T object) @safe handler) {
  return postWith!(Policy, T, V)(router, handler.toDelegate);
}

/// ditto
URLRouter postWith(Policy, Type)(URLRouter router, void delegate(Type object, HTTPServerResponse res) @safe handler) {
  FieldDefinition definition = getFields!Type;
  auto rule = Policy.create(definition);

  auto deserializationHandler = requestFullDeserializationHandler!Policy(handler, rule);

  return router.post(rule.request.path, requestErrorHandler(deserializationHandler));
}

/// ditto
URLRouter postWith(Policy, Type, V)(URLRouter router, V delegate(Type object) @safe handler) {
  FieldDefinition definition = getFields!Type;
  auto rule = Policy.create(definition);

  auto deserializationHandler = requestDeserializationHandler!Policy(handler, rule);

  return router.post(rule.request.path, requestErrorHandler(deserializationHandler));
}



///
URLRouter postJsonWith(Policy, Type, V)(URLRouter router, V function(Json object) @safe handler) {
  return postJsonWith!(Policy, Type)(router, handler.toDelegate);
}

/// ditto
URLRouter postJsonWith(Policy, Type, V)(URLRouter router, V delegate(Json object) @safe next) {
  FieldDefinition definition = getFields!Type;
  auto rule = Policy.create(definition);

  auto handler = requestDeserializedHandler!(Policy, Type)(next, rule);

  return router.post(rule.request.path, requestErrorHandler(handler));
}



/// Add a DELETE route that parse the data according a Protocol
URLRouter deleteWith(Policy, Type)(URLRouter router, void function(string id, HTTPServerResponse res) @safe handler) {
  return deleteWith!(Policy, Type)(router, handler.toDelegate);
}

/// ditto
URLRouter deleteWith(Policy, Type)(URLRouter router, void function(string id) @safe handler) {
  return deleteWith!(Policy, Type)(router, handler.toDelegate);
}

/// ditto
URLRouter deleteWith(Policy, Type)(URLRouter router, void delegate(string id, HTTPServerResponse res) @safe handler) {
  FieldDefinition definition = getFields!Type;
  auto rule = Policy.delete_(definition);

  enforce(rule.request.path.endsWith("/:id"), "Invalid `" ~ rule.request.path ~ "` route. It must end with `/:id`.");
  auto idHandler = requestIdHandler(handler, rule);

  return router.delete_(rule.request.path, requestErrorHandler(idHandler));
}
/// ditto
URLRouter deleteWith(Policy, Type)(URLRouter router, void delegate(string id) @safe handler) {
  FieldDefinition definition = getFields!Type;
  auto rule = Policy.delete_(definition);
  
  enforce(rule.request.path.endsWith("/:id"), "Invalid `" ~ rule.request.path ~ "` route. It must end with `/:id`.");
  auto idHandler = requestIdHandler(handler, rule);

  return router.addRule(rule, requestErrorHandler(idHandler));
}

/// add a GET route that returns to the client one item selected by id
URLRouter getWith(Policy, Type)(URLRouter router, Type function(string id) @safe handler) if(!is(Type == void)) {
  return getWith!(Policy, Type)(router, handler.toDelegate);
}

/// ditto
URLRouter getWith(Policy, Type)(URLRouter router, void function(string id, HTTPServerResponse res) @safe handler) if(!is(T == void)) {
  return getWith!(Policy, Type)(router, handler.toDelegate);
}

/// ditto
URLRouter getWith(Policy, Type)(URLRouter router, Type delegate(string id) @safe handler) if(!is(Type == void)) {
  FieldDefinition definition = getFields!Type;
  auto rule = Policy.getItem(definition);

  enforce(rule.request.path.endsWith("/:id"), "Invalid `" ~ rule.request.path ~ "` route. It must end with `/:id`.");
  auto idHandler = requestIdHandler(handler, rule);

  return router.addRule(rule, requestErrorHandler(idHandler));
}

/// ditto
URLRouter getWith(Policy, Type)(URLRouter router, ICrateSelector delegate(string id) @safe handler) if(!is(T == void)) {
  Type resultExtractor(string id) @trusted {
    auto result = handler(id).exec;

    enforce!CrateNotFoundException(!result.empty, "Missing `" ~ Type.stringof ~ "`.");

    return result.front.deserializeJson!Type;
  }

  return getWith!(Policy, Type)(router, &resultExtractor);
}

/// ditto
URLRouter getWith(Policy, Type)(URLRouter router, void delegate(string id, HTTPServerResponse res) @safe handler) if(!is(Type == void)) {
  FieldDefinition definition = getFields!Type;
  auto rule = Policy.getItem(definition);

  enforce(rule.request.path.endsWith("/:id"), "Invalid `" ~ rule.request.path ~ "` route. It must end with `/:id`.");
  auto idHandler = requestIdHandler(handler, rule);

  return router.addRule(rule, requestErrorHandler(idHandler));
}

/// GET list
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
URLRouter getListFilteredWith(Policy, Type)(URLRouter router, ICrateSelector delegate() @safe handler, ICrateFilter[] filters ...) {
  FieldDefinition definition = getFields!Type;
  auto rule = Policy.getList(definition);

  auto listHandler = requestFilteredListHandler!(Policy, Type)(handler, filters);

  return addRule(router, rule, listHandler);
}

URLRouter addRule(T)(URLRouter router, CrateRule rule, T handler) {
  router.addApi(rule);

  return router.match(rule.request.method, rule.request.path, handler);
}

/// Call a method from a structure by passing the body data
URLRouter enableAction(Policy, Type, string actionName, T)(URLRouter router, T getHandler) {
  alias Method = typeof(__traits(getMember, Type, actionName));
  alias MethodReturnType = ReturnType!Method;

  static if(Parameters!Method.length == 0) {
    alias ParameterType = void;
  } else static if(Parameters!Method.length == 1) {
    alias ParameterType = Parameters!Method[0];
  } else {
    static assert(false, "enableAction works only with no or one parameter");
  }

  FieldDefinition definition = getFields!Type;
  auto rule = Policy.action!(MethodReturnType, ParameterType, actionName)(definition);

  enforce(rule.request.path.canFind("/:id/"), "Invalid `" ~ rule.request.path ~ "` route. It must contain `/:id/`.");

  static if(isDelegate!T) {
    alias _getHandler = getHandler;
  } else {
    auto _getHandler = getHandler.toDelegate;
  }

  void nullSink(Type) { }

  auto actionHandler = requestActionHandler!(Type, actionName)(_getHandler, &nullSink, rule);

  return router.addRule(rule, requestErrorHandler(actionHandler));
}

/// ditto
URLRouter enableAction(Policy, Type, string actionName, T, U)(URLRouter router, T getHandler, U updateHandler) {
  alias Method = typeof(__traits(getMember, Type, actionName));
  alias MethodReturnType = ReturnType!Method;

  static if(Parameters!Method.length == 0) {
    alias ParameterType = void;
  } else static if(Parameters!Method.length == 1) {
    alias ParameterType = Parameters!Method[0];
  } else {
    static assert(false, "enableAction works only with no or one parameter");
  }

  FieldDefinition definition = getFields!Type;
  auto rule = Policy.action!(MethodReturnType, ParameterType, actionName)(definition);

  enforce(rule.request.path.canFind("/:id/"), "Invalid `" ~ rule.request.path ~ "` route. It must contain `/:id/`.");

  static if(isDelegate!T) {
    alias _getHandler = getHandler;
  } else {
    auto _getHandler = getHandler.toDelegate;
  }

  static if(isDelegate!U) {
    alias _updateHandler = updateHandler;
  } else {
    auto _updateHandler = updateHandler is null ? null : updateHandler.toDelegate;
  }

  auto actionHandler = requestActionHandler!(Type, actionName)(_getHandler, _updateHandler, rule);

  return router.addRule(rule, requestErrorHandler(actionHandler));
}

private string createResourceAccess(string resourcePath) {
  auto parts = resourcePath.split("/");

  string res = "";

  foreach(part; parts) {
    if(part == "") {
      continue;
    }

    if(part[0] == ':') {
      res ~= "[request.params[\"" ~ part[1 .. $] ~ "\"].to!ulong]";
    } else {
      res ~= "." ~ part;
    }
  }

  return res;
}

/// ditto
auto getResourceHandler(Type, string resourcePath, T)(T delegate(string) @safe next, CrateRule rule) if(!is(T == void)) {
  import std.stdio;
  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @trusted {
    string id = request.params["id"];

    Type value;

    try {
      static if(is(T == Json)) {
        value = next(id).deserializeJson!Type;
      } else static if(is(T == ICrateSelector)) {
        auto result = next(id).exec;
        enforce!CrateNotFoundException(!result.empty, "Missing `" ~ Type.stringof ~ "`.");

        value = result.front.deserializeJson!Type;
      } else {
        value = next(id);
      }
    } catch (JSONException e) {
      throw new CrateValidationException("Can not deserialize data. " ~ e.msg, e.file, e.line);
    }

    mixin("auto obj = value" ~ resourcePath.createResourceAccess ~ ";");

    response.headers["Content-Type"] = obj.contentType;

    if(obj.hasSize) {
      response.headers["Content-Length"] = obj.size.to!string;
    }

    response.statusCode = rule.response.statusCode;

    obj.write(response.bodyWriter);
  }

  return &deserialize;
}

URLRouter getResource(Policy, Type, string resourcePath, T)(URLRouter router, T getItem) {
  FieldDefinition definition = getFields!Type;

  auto rule = Policy.getResource!resourcePath(definition);
  
  auto handler = getResourceHandler!(Type, resourcePath)(getItem, rule);

  return router.addRule(rule, requestErrorHandler(handler));
}

auto setResourceHandler(Type, string resourcePath, T, U)(T delegate(string) @safe getItem, U updateItem, CrateRule rule) if(!is(T == void)) {
  import std.stdio;
  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @trusted {
    string id = request.params["id"];
    auto pathItems = resourcePath.split("/");
    auto resourceName = pathItems[pathItems.length - 1];

    Type value;

    try {
      static if(is(T == Json)) {
        value = getItem(id).deserializeJson!Type;
      } else static if(is(T == ICrateSelector)) {
        auto result = getItem(id).exec;
        enforce!CrateNotFoundException(!result.empty, "Missing `" ~ Type.stringof ~ "`.");

        value = result.front.deserializeJson!Type;
      } else {
        value = getItem(id);
      }
    } catch (JSONException e) {
      throw new CrateValidationException("Can not deserialize data. " ~ e.msg, e.file, e.line);
    }

    mixin("auto obj = value" ~ resourcePath.createResourceAccess ~ ";");

    enforce!CrateValidationException(resourceName in request.files, "`" ~ resourceName ~ "` attachement not found.");

    auto file = request.files.get(resourceName);
    obj.read(file);

    updateItem(value.serializeToJson);

    response.writeBody("", rule.response.statusCode);
  }

  return &deserialize;
}

URLRouter setResource(Policy, Type, string resourcePath, T, U)(URLRouter router, T getItem, U updateItem) {
  FieldDefinition definition = getFields!Type;

  auto rule = Policy.setResource!resourcePath(definition);
  auto handler = setResourceHandler!(Type, resourcePath)(getItem, updateItem, rule);

  return router.addRule(rule, requestErrorHandler(handler));
}