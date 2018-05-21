module crate.http.handlers.resource;

import std.exception;
import std.string;
import std.functional;
import std.traits;
import std.conv;
import std.algorithm;

import crate.ctfe;
import crate.base;
import crate.error;
import crate.http.handlers.request;
import crate.http.handlers.error;
import crate.http.resource;
import vibe.http.router;
import vibe.data.json;

private string createResourceAccess(string resourcePath) {
  auto parts = resourcePath.split("/");

  string res = "";

  foreach(part; parts) {
    if(part == "") {
      continue;
    }

    if(part[0] == ':') {
      res ~= "[request.params[\"" ~ part[1 .. $] ~ "\"].to!ulong]";
    } else {
      res ~= "." ~ part;
    }
  }

  return res;
}

/// ditto
auto getResourceHandler(Type, string resourcePath, T)(T delegate(string) @safe next, CrateRule rule) if(!is(T == void)) {
  import std.stdio;
  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @trusted {
    string id = request.params["id"];

    Type value;

    try {
      static if(is(T == Json)) {
        value = next(id).deserializeJson!Type;
      } else static if(is(T == ICrateSelector)) {
        auto result = next(id).exec;
        enforce!CrateNotFoundException(!result.empty, "Missing `" ~ Type.stringof ~ "`.");

        value = result.front.deserializeJson!Type;
      } else {
        value = next(id);
      }
    } catch (JSONException e) {
      throw new CrateValidationException("Can not deserialize data. " ~ e.msg, e.file, e.line);
    }

    mixin("auto obj = value" ~ resourcePath.createResourceAccess ~ ";");

    response.headers["Content-Type"] = obj.contentType;

    if(obj.hasSize) {
      response.headers["Content-Length"] = obj.size.to!string;
    }

    response.statusCode = rule.response.statusCode;

    obj.write(response.bodyWriter);
  }

  return &deserialize;
}

URLRouter getResource(Policy, Type, string resourcePath, T)(URLRouter router, T getItem) {
  FieldDefinition definition = getFields!Type;

  auto rule = Policy.getResource!resourcePath(definition);
  
  auto handler = getResourceHandler!(Type, resourcePath)(getItem, rule);

  return router.addRule(rule, requestErrorHandler(handler));
}

auto setResourceHandler(Type, string resourcePath, T, U)(T delegate(string) @safe getItem, U updateItem, CrateRule rule) if(!is(T == void)) {
  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @trusted {
    string id = request.params["id"];
    auto pathItems = resourcePath.split("/");
    auto resourceName = pathItems[pathItems.length - 1];

    Type value;

    try {
      static if(is(T == Json)) {
        value = getItem(id).deserializeJson!Type;
      } else static if(is(T == ICrateSelector)) {
        auto result = getItem(id).exec;
        enforce!CrateNotFoundException(!result.empty, "Missing `" ~ Type.stringof ~ "`.");

        value = result.front.deserializeJson!Type;
      } else {
        value = getItem(id);
      }
    } catch (JSONException e) {
      throw new CrateValidationException("Can not deserialize data. " ~ e.msg, e.file, e.line);
    }

    mixin("auto obj = value" ~ resourcePath.createResourceAccess ~ ";");

    enforce!CrateValidationException(resourceName in request.files, "`" ~ resourceName ~ "` attachement not found.");

    auto file = request.files.get(resourceName);
    obj.read(file);

    updateItem(value.serializeToJson);

    response.writeBody("", rule.response.statusCode);
  }

  return &deserialize;
}

URLRouter setResource(Policy, Type, string resourcePath, T, U)(URLRouter router, T getItem, U updateItem) {
  enum FieldDefinition definition = getFields!Type;

  auto rule = Policy.setResource!resourcePath(definition);
  auto handler = setResourceHandler!(Type, resourcePath)(getItem, updateItem, rule);

  return router.addRule(rule, requestErrorHandler(handler));
}
