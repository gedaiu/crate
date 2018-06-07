module crate.http.handlers.get_list;

import std.exception;
import std.string;
import std.functional;

import crate.ctfe;
import crate.base;
import crate.http.handlers.request;
import crate.http.handlers.error;
import vibe.http.router;
import vibe.data.json;


/// GET list
URLRouter getListWith(Policy, T)(URLRouter router, string route, T[] function() @safe handler) if(!is(T == void)) {
  return getListWith!(Policy, T)(router, route, handler.toDelegate);
}

/// ditto
URLRouter getListWith(Policy, T)(URLRouter router, T[] function() @safe handler) if(!is(T == void)) {
  return getListWith!(Policy, T)(router, handler.toDelegate);
}

/// ditto
URLRouter getListWith(Policy, Type)(URLRouter router, string route, Type[] delegate() @safe handler) if(!is(Type == void)) {
  FieldDefinition definition = getFields!Type;
  auto rule = Policy.getList(definition);

  auto listHandler = requestListHandler!(Policy, Type)(handler);

  return router.addRule(rule, requestErrorHandler(listHandler));
}

/// ditto
URLRouter getListWith(Policy, T)(URLRouter router, T[] delegate() @safe handler) if(!is(T == void)) {
  FieldDefinition definition = getFields!T;
  auto routing = new Policy.Routing(definition);

  return getListWith!(Policy, T)(router, routing.getList, handler.toDelegate);
}

/// ditto
URLRouter getListFilteredWith(Policy, Type, Filters...)(URLRouter router, ICrateSelector delegate() @safe handler, Filters filters) {
  FieldDefinition definition = getFields!Type;
  auto rule = Policy.getList(definition);

  auto listHandler = requestFilteredListHandler!(Policy, Type)(handler, filters);

  return addRule(router, rule, requestErrorHandler(listHandler));
}