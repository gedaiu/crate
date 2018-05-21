module crate.http.handlers.put;

import std.exception;
import std.string;
import std.functional;

import crate.ctfe;
import crate.base;
import crate.http.handlers.request;
import crate.http.handlers.error;
import vibe.http.router;
import vibe.data.json;

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

  return router.addRule(rule, requestErrorHandler(deserializationHandler));
}

/// ditto
URLRouter putWith(Policy, Type, V)(URLRouter router, V delegate(Type object) @safe next) {
  FieldDefinition definition = getFields!Type;
  auto rule = Policy.replace(definition);

  enforce(rule.request.path.endsWith("/:id"), "Invalid `" ~ rule.request.path ~ "` route. It must end with `/:id`.");
  auto handler = requestDeserializationHandler!Policy(next, rule);

  return router.addRule(rule, requestErrorHandler(handler));
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

  return router.addRule(rule, requestErrorHandler(handler));
}