module crate.http.handlers.get;

import std.exception;
import std.string;
import std.functional;

import crate.ctfe;
import crate.base;
import crate.http.handlers.request;
import crate.http.handlers.error;
import vibe.http.router;

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
URLRouter getWith(Policy, Type, Filters...)(URLRouter router, ICrateSelector delegate(string id) @safe handler, Filters filters) if(!is(T == void)) {
  FieldDefinition definition = getFields!Type;
  auto rule = Policy.getItem(definition);

  enforce(rule.request.path.endsWith("/:id"), "Invalid `" ~ rule.request.path ~ "` route. It must end with `/:id`.");
  auto idHandler = requestIdHandler(handler, rule, filters);

  return router.addRule(rule, requestErrorHandler(idHandler));
}

/// ditto
URLRouter getWith(Policy, Type)(URLRouter router, void delegate(string id, HTTPServerResponse res) @safe handler) if(!is(Type == void)) {
  FieldDefinition definition = getFields!Type;
  auto rule = Policy.getItem(definition);

  enforce(rule.request.path.endsWith("/:id"), "Invalid `" ~ rule.request.path ~ "` route. It must end with `/:id`.");
  auto idHandler = requestIdHandler(handler, rule);

  return router.addRule(rule, requestErrorHandler(idHandler));
}