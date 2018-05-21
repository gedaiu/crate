module crate.http.handlers.delete_;

import std.exception;
import std.string;
import std.functional;

import crate.ctfe;
import crate.base;
import crate.http.handlers.request;
import crate.http.handlers.error;
import vibe.http.router;
import vibe.data.json;


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

  return router.addRule(rule, requestErrorHandler(idHandler));
}
/// ditto
URLRouter deleteWith(Policy, Type)(URLRouter router, void delegate(string id) @safe handler) {
  FieldDefinition definition = getFields!Type;
  auto rule = Policy.delete_(definition);
  
  enforce(rule.request.path.endsWith("/:id"), "Invalid `" ~ rule.request.path ~ "` route. It must end with `/:id`.");
  auto idHandler = requestIdHandler(handler, rule);

  return router.addRule(rule, requestErrorHandler(idHandler));
}

