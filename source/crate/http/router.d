module crate.http.router;

import crate.error;
import crate.base;
import crate.ctfe;
import crate.collection.proxy;
import crate.http.methodcollection;
import crate.http.action.model;
import crate.http.action.crate;
import crate.generator.openapi;

import crate.policy.jsonapi;
import crate.policy.restapi;

import vibe.data.json;
import vibe.http.router;
import vibe.stream.operations;

import std.conv;
import std.string;
import std.traits;
import std.stdio;
import std.functional;
import std.exception;
import std.algorithm;
import std.array;
import std.range.interfaces;

import crate.http.handlers.error;
import crate.http.handlers.get;
import crate.http.handlers.put;
import crate.http.handlers.patch;
import crate.http.handlers.post;
import crate.http.handlers.delete_;
import crate.http.handlers.get_list;
import crate.http.handlers.action;
import crate.http.handlers.resource;

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
    crateGetters[Type.stringof] = &crate.getItem;

    router.putJsonWith!(Policy, Type)(&crate.updateItem);
    router.postJsonWith!(Policy, Type)(&crate.addItem);
    router.patchJsonWith!(Policy, Type)(&crate.updateItem, &crate.getItem);
    router.deleteWith!(Policy, Type)(&crate.deleteItem);
    router.getWith!(Policy, Type)(&crate.getItem, filters);
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
      \"description\": \"`position` is required.\", 
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
