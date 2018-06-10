module crate.http.handlers.delete_;

import std.exception;
import std.string;
import std.functional;
import std.traits;

import crate.ctfe;
import crate.base;
import crate.http.handlers.request;
import crate.http.handlers.error;
import crate.error;

import vibe.http.router;
import vibe.data.json;

class DeleteOperation(Policy, Type) {
  alias DelegateResponseHandler = void delegate(string id, HTTPServerResponse res) @safe;
  alias DelegateHandler = void delegate(string id) @safe;

  private {
    URLRouter router;
    DelegateHandler _handler;
    DelegateResponseHandler _responseHandler;
    IFiltersWrapper filters;
  }

  this(URLRouter router) {
    this.router = router;
  }

  /// Set the delete handler
  void handler(DelegateResponseHandler value) {
    _responseHandler = value;
  }

  /// ditto
  void handler(DelegateHandler value) {
    _handler = value;
  }

  /// ditto
  void handler(void function(string id, HTTPServerResponse res) @safe value) {
    handler(value.toDelegate);
  }

  /// ditto
  void handler(void function(string id) @safe value) {
    handler(value.toDelegate);
  }

  /// Set the get item function
  void getItem(Types...)(IFiltersWrapper.GetItemDelegate value, Types middlewares) {
    filters = new FiltersWrapper!Types(middlewares);
    filters.getItem = value;
  }

  URLRouter bind() {
    FieldDefinition definition = getFields!Type;
    auto rule = Policy.delete_(definition);

    enforce(rule.request.path.endsWith("/:id"), "Invalid `" ~ rule.request.path ~ "` route. It must end with `/:id`.");

    VibeHandler next;

    if(_handler !is null) {
      next = requestIdHandler(_handler, rule);
    } else {
      next = requestIdHandler(_responseHandler, rule);
    }

    if(filters is null) {
      return router.addRule(rule, requestErrorHandler(next));
    } else {
      return router.addRule(rule, requestErrorHandler(filters.handler(next)));
    }
  }
}
