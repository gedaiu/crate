module crate.http.cors;

import std.algorithm;
import std.array;
import std.conv;
import std.string;
import vibe.http.router;

void addHeaderValue(ref HTTPServerResponse res, string name, string[] values) {
  if(name in res.headers) {
    values = res.headers[name].split(",") ~ values;
  }

  res.headers[name] = values.map!(a => a.strip).uniq.filter!(a => a != "").join(", ");
}

class Cors {

  private {
    static Cors[string][URLRouter] cache;
    HTTPMethod[] methods;
  }

  static Cors opCall(URLRouter router, string route) {
    if(router !in cache || route !in cache[router]) {
      auto cors = new Cors();
      cache[router][route] = cors;

      router.match(HTTPMethod.OPTIONS, route, cors.add(HTTPMethod.OPTIONS));
    }

    return cache[router][route];
  }

  void nothing(HTTPServerRequest request, HTTPServerResponse response) {
      response.statusCode = 200;
      response.writeBody("");
  }

  auto add(HTTPMethod method, void delegate(HTTPServerRequest, HTTPServerResponse) next = null) {
    if(next is null) {
      next = &this.nothing;
    }

    methods ~= method;

    void cors(HTTPServerRequest request, HTTPServerResponse response) {
      response.addHeaderValue("Access-Control-Allow-Origin", ["*"]);
      response.addHeaderValue("Access-Control-Allow-Methods", methods.map!(a => a.to!string).array);
      response.addHeaderValue("Access-Control-Allow-Headers", ["Content-Type"]);

      next(request, response);
    }

    return &cors;
  }
}