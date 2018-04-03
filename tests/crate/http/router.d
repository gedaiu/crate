module tests.crate.http;

import trial.interfaces;

import trial.step;
import trial.runner;
import trial.discovery.spec;
import fluent.asserts;
import fluentasserts.vibe.request;


import vibe.data.json;
import vibe.http.router;

import crate.http.router;

struct Point {
  string type = "Point";
  float[2] coordinates;
}

struct Site {
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

Site putSite(Site site, HTTPServerResponse res) @safe {
  return site;
}

alias s = Spec!({
  describe("The crate router", {

    it("should accept a PUT with REST Api structure", {
      auto router = new URLRouter();
      router.putRestApi("/sites/:id", &putSite);

      Json dataUpdate = `{ "site": {
          "position": {
            "type": "Point",
            "coordinates": [0, 0]
          }
      }}`.parseJsonString;

      request(router)
        .put("/sites/10")
          .send(dataUpdate)
            .expectStatusCode(200)
            .end((Response response) => {
              dataUpdate["site"]["_id"] = "10";
              response.bodyJson.should.equal(dataUpdate);
            });
    });

    it("should validate a PUT route", {
      auto router = new URLRouter();
      ({
        router.putRestApi("/sites/:_id", &putSite);
      }).should.throwAnyException.withMessage("Invalid `/sites/:_id` route. It must end with `/:id`.");
    });

    it("should validate the structure", {
      auto router = new URLRouter();
      router.putRestApi("/sites/:id", &putSite);

      auto dataUpdate = `{ "site": { }}`.parseJsonString;
      auto expectedError = `{"errors": [{
        "description": "Can not deserialize data. Got .site.position of type undefined, expected object.", 
        "title": "Validation error", 
        "status": 400 }]}`.parseJsonString;

      request(router)
        .put("/sites/10")
          .send(dataUpdate)
            .expectStatusCode(400)
            .end((Response response) => {
              response.bodyJson.should.equal(expectedError);
            });
    });
  });
});