module crate.http.handlers.patch;

import std.exception;
import std.string;
import std.functional;

import crate.ctfe;
import crate.base;
import crate.http.handlers.request;
import crate.http.handlers.error;
import vibe.http.router;
import vibe.data.json;


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
