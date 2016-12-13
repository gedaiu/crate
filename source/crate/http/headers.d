module crate.http.headers;

import vibe.http.common;
import std.stdio;
import std.string;
import std.array;
import std.algorithm;

void addHeaderValues(HTTPResponse response, const string name, string[] values) {
  if(name in response.headers) {
    values = response.headers[name].split(",") ~ values;
  }

  response.headers[name] = values.map!(a => a.strip).uniq.join(", ");
}

@("it should create the header if does not exist")
unittest {
  auto response = new HTTPResponse;

  response.addHeaderValues("key1", ["value"]);
  response.addHeaderValues("key2", ["value1", "value2"]);

  assert(response.headers["key1"] == "value");
  assert(response.headers["key2"] == "value1, value2");
}

@("it should append the header values if already exists")
unittest {
  auto response = new HTTPResponse;

  response.addHeaderValues("key1", ["value1"]);
  response.addHeaderValues("key1", ["value2"]);

  response.addHeaderValues("key2", ["value1", "value2"]);
  response.addHeaderValues("key2", ["value3"]);

  assert(response.headers["key1"] == "value1, value2");
  assert(response.headers["key2"] == "value1, value2, value3");
}


@("it should add twice the same value")
unittest {
  auto response = new HTTPResponse;

  response.addHeaderValues("key", ["value"]);
  response.addHeaderValues("key", ["value"]);

  assert(response.headers["key"] == "value");
}
