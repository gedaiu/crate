module tests.crate.http.mocks;

import vibe.data.json;


struct TestModel
{
  @optional string _id = "1";
  string name = "";

  void actionChange()
  {
    name = "changed";
  }

  void actionParam(string data)
  {
    name = data;
  }
}

struct Point
{
  string type = "Point";
  float[2] coordinates;
}

struct Site
{
  string _id = "1";
  Point position;

  Json toJson() const @safe {
    Json data = Json.emptyObject;

    data["_id"] = _id;
    data["position"] = position.serializeToJson;

    return data;
  }

  static Site fromJson(Json src) @safe {
    return Site(
      src["_id"].to!string,
      Point("Point", [ src["position"]["coordinates"][0].to!int, src["position"]["coordinates"][1].to!int ])
    );
  }
}