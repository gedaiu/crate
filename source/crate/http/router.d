module crate.http.router;

import crate.error;
import crate.base;
import crate.ctfe;
import crate.collection.proxy;
import crate.http.action.model;
import crate.http.action.crate;
import crate.generator.openapi;

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

import crate.api.rest.policy;
alias DefaultPolicy = crate.api.rest.policy.CrateRestApiPolicy;

string basePath(T)(string name, const CrateConfig!T config)
{
  static if (isAggregateType!T || is(T == void))
  {
    if (name == "Json API")
    {
      return crate.api.json.policy.basePath(config);
    }

    if (name == "Rest API")
    {
      return crate.api.rest.policy.basePath(config);
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
