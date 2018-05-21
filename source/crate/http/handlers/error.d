module crate.http.handlers.error;

import std.functional;

import crate.error;

import vibe.data.json;
import vibe.http.router;

auto requestErrorHandler(void function(HTTPServerRequest, HTTPServerResponse) @safe next) {
  return requestErrorHandler(next.toDelegate);
}

auto requestErrorHandler(void delegate(HTTPServerRequest, HTTPServerResponse) @safe next) {
  void check(HTTPServerRequest request, HTTPServerResponse response) @trusted {
    try {
      next(request, response);
    } catch(CrateException e) {
      response.writeJsonBody(e.toJson, e.statusCode);
    } catch (Exception e) {
      debug {
        import std.stdio;
        e.writeln;
      }
      Json data = e.toJson;
      response.writeJsonBody(data, data["errors"][0]["status"].to!int);
    }
  }
  
  return &check;
}