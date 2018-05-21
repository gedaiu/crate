module crate.http.handlers.action;

import std.exception;
import std.string;
import std.functional;
import std.traits;
import std.algorithm;

import crate.ctfe;
import crate.base;
import crate.http.handlers.request;
import crate.http.handlers.error;
import vibe.http.router;
import vibe.data.json;



/// Call a method from a structure by passing the body data
URLRouter enableAction(Policy, Type, string actionName, T)(URLRouter router, T getHandler) {
  alias Method = typeof(__traits(getMember, Type, actionName));
  alias MethodReturnType = ReturnType!Method;

  static if(Parameters!Method.length == 0) {
    alias ParameterType = void;
  } else static if(Parameters!Method.length == 1) {
    alias ParameterType = Parameters!Method[0];
  } else {
    static assert(false, "enableAction works only with no or one parameter");
  }

  FieldDefinition definition = getFields!Type;
  auto rule = Policy.action!(MethodReturnType, ParameterType, actionName)(definition);

  enforce(rule.request.path.canFind("/:id/"), "Invalid `" ~ rule.request.path ~ "` route. It must contain `/:id/`.");

  static if(isDelegate!T) {
    alias _getHandler = getHandler;
  } else {
    auto _getHandler = getHandler.toDelegate;
  }

  void nullSink(Type) { }

  auto actionHandler = requestActionHandler!(Type, actionName)(_getHandler, &nullSink, rule);

  return router.addRule(rule, requestErrorHandler(actionHandler));
}

/// ditto
URLRouter enableAction(Policy, Type, string actionName, T, U)(URLRouter router, T getHandler, U updateHandler) {
  alias Method = typeof(__traits(getMember, Type, actionName));
  alias MethodReturnType = ReturnType!Method;

  static if(Parameters!Method.length == 0) {
    alias ParameterType = void;
  } else static if(Parameters!Method.length == 1) {
    alias ParameterType = Parameters!Method[0];
  } else {
    static assert(false, "enableAction works only with no or one parameter");
  }

  FieldDefinition definition = getFields!Type;
  auto rule = Policy.action!(MethodReturnType, ParameterType, actionName)(definition);

  enforce(rule.request.path.canFind("/:id/"), "Invalid `" ~ rule.request.path ~ "` route. It must contain `/:id/`.");

  static if(isDelegate!T) {
    alias _getHandler = getHandler;
  } else {
    auto _getHandler = getHandler.toDelegate;
  }

  static if(isDelegate!U) {
    alias _updateHandler = updateHandler;
  } else {
    auto _updateHandler = updateHandler is null ? null : updateHandler.toDelegate;
  }

  auto actionHandler = requestActionHandler!(Type, actionName)(_getHandler, _updateHandler, rule);

  return router.addRule(rule, requestErrorHandler(actionHandler));
}
