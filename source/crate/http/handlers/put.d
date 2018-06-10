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

///
auto toJsonDelegate(R, P)(R delegate(P value) @safe value) {
  auto jsonWrapper(Json parameter) {
    static if(is(P == Json)) {
      auto param = parameter;
    } else {
      auto param = parameter.deserializeJson!P;
    }

    Json jsonResult;
    static if(is(R == void)) {
      jsonResult = Json.undefined;
      value(param);
    } else static if(is(R == Json)) {
      jsonResult = value(param);
    } else {
      jsonResult = value(param).serializeToJson;
    }

    return jsonResult;
  }
  
  return &jsonWrapper;
}


///
auto toJsonDelegate(R, P)(R delegate(P value, HTTPServerResponse res) @safe value) {
  void jsonWrapper(Json parameter, HTTPServerResponse res) {
    static if(is(P == Json)) {
      auto param = parameter;
    } else {
      auto param = parameter.deserializeJson!P;
    }

    value(param, res);
  }
  
  return &jsonWrapper;
}

class PutOperation(Policy, Type) {
  alias DelegateResponseHandler = void delegate(Json value, HTTPServerResponse res) @safe;
  alias DelegateHandler = Json delegate(Json value) @safe;

  private {
    URLRouter router;
    DelegateHandler _handler;
    DelegateResponseHandler _responseHandler;

    IFiltersWrapper filters;
  }

  /// Set the get item function
  void getItem(Types...)(IFiltersWrapper.GetItemDelegate value, Types middlewares) {
    filters = new FiltersWrapper!Types(middlewares);
    filters.getItem = value;
  }

  /// Set the put handler
  void handler(DelegateHandler value) {
    this._handler = value;
  }

  /// ditto
  void handler(R, P)(R function(P value) @safe value) {
    this._handler = value.toDelegate.toJsonDelegate;
  }

  /// ditto
  void handler(R, P)(R delegate(P value) @safe value) {
    this._handler = value.toJsonDelegate;
  }


  /// ditto
  void handler(DelegateResponseHandler value) {
    this._responseHandler = value;
  }

  /// ditto
  void handler(R, P)(R function(P value, HTTPServerResponse res) @safe value) {
    this._responseHandler = value.toDelegate.toJsonDelegate;
  }

  /// ditto
  void handler(R, P)(R delegate(P value, HTTPServerResponse res) @safe value) {
    this._responseHandler = value.toJsonDelegate;
  }

  this(URLRouter router) {
    this.router = router;
  }

  URLRouter bind(Types...)(Types middlewares) {
    FieldDefinition definition = getFields!Type;
    auto rule = Policy.replace(definition);

    enforce(rule.request.path.endsWith("/:id"), "Invalid `" ~ rule.request.path ~ "` route. It must end with `/:id`.");

    VibeHandler next;

    if(_handler !is null) {
      next = requestDeserializationHandler!Type(_handler, rule);
    } else {
      next = requestDeserializationHandler!Type(_responseHandler, rule);
    }

    if(filters is null) {
      return router.addRule(rule, requestErrorHandler(next));
    } else {
      return router.addRule(rule, requestErrorHandler(filters.handler(next)));
    }
  }
}
