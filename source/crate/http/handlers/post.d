module crate.http.handlers.post;

import std.exception;
import std.string;
import std.functional;

import crate.ctfe;
import crate.base;
import crate.http.handlers.request;
import crate.http.handlers.error;
import vibe.http.router;
import vibe.data.json;

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

  return router.addRule(rule, requestErrorHandler(deserializationHandler));
}

/// ditto
URLRouter postWith(Policy, Type, V)(URLRouter router, V delegate(Type object) @safe handler) {
  FieldDefinition definition = getFields!Type;
  auto rule = Policy.create(definition);

  auto deserializationHandler = requestDeserializationHandler!Policy(handler, rule);

  return router.addRule(rule, requestErrorHandler(deserializationHandler));
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

  return router.addRule(rule, requestErrorHandler(handler));
}

