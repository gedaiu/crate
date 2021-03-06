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
import vibeauth.router.oauth;

import std.conv;
import std.traits;
import std.functional;
import std.exception;
import std.algorithm;
import std.array;
import std.range.interfaces;
import std.stdio;

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

  CrateRouter enable(OAuth2 auth) {
    router.any("*", &auth.tokenHandlers);

    return this;
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

  CrateRouter add(Type, T...)(Crate!Type crate, T middleware) {
    return add!RouterPolicy(crate, middleware);
  }

  CrateRouter add(Policy, Type, T...)(Crate!Type crate, T middleware) {
    foreach(item; middleware) {
      addOneMiddleware!(Policy, Type)(item);
    }

    crateGetters[Type.stringof] = &crate.getItem;

    auto deleteOperation = new DeleteOperation!(Policy, Type)(router);
    deleteOperation.handler = &crate.deleteItem;
    deleteOperation.getItem(&crate.getItem, middleware);
    deleteOperation.bind();

    auto putOperation = new PutOperation!(Policy, Type)(router);
    putOperation.handler = &crate.updateItem;
    putOperation.getItem(&crate.getItem, middleware);
    putOperation.bind();

    router.postJsonWith!(Policy, Type)(&crate.addItem);
    router.patchJsonWith!(Policy, Type)(&crate.updateItem, &crate.getItem);
    router.getWith!(Policy, Type)(&crate.getItem, middleware);
    router.getListFilteredWith!(Policy, Type)(&crate.getList, middleware);

    return this;
  }

  private void addOneMiddleware(Policy, Type, T)(T middleware) {
    CrateRule rule;
    FieldDefinition definition;

    definition = getFields!Type;

    static if(isVibeHandler!(T, "any")) {
      rule = Policy.getList(definition);
      router.match(rule.request.method, rule.request.path, &middleware.any);

      rule = Policy.getItem(definition);
      router.match(rule.request.method, rule.request.path, &middleware.any);

      rule = Policy.create(definition);
      router.match(rule.request.method, rule.request.path, &middleware.any);

      rule = Policy.replace(definition);
      router.match(rule.request.method, rule.request.path, &middleware.any);

      rule = Policy.patch(definition);
      router.match(rule.request.method, rule.request.path, &middleware.any);

      rule = Policy.delete_(definition);
      router.match(rule.request.method, rule.request.path, &middleware.any);
    }

    static if(isVibeHandler!(T, "getList")) {
      rule = Policy.getList(definition);
      router.match(rule.request.method, rule.request.path, &middleware.getList);
    }

    static if(isVibeHandler!(T, "getItem")) {
      rule = Policy.getItem(definition);
      router.match(rule.request.method, rule.request.path, &middleware.getItem);
    }

    static if(isVibeHandler!(T, "create")) {
      rule = Policy.create(definition);
      router.match(rule.request.method, rule.request.path, &middleware.create);
    }

    static if(isVibeHandler!(T, "replace")) {
      rule = Policy.replace(definition);
      router.match(rule.request.method, rule.request.path, &middleware.replace);
    }

    static if(isVibeHandler!(T, "patch")) {
      rule = Policy.patch(definition);
      router.match(rule.request.method, rule.request.path, &middleware.patch);
    }

    static if(isVibeHandler!(T, "delete_")) {
      rule = Policy.delete_(definition);
      router.match(rule.request.method, rule.request.path, &middleware.delete_);
    }
  }
}
