module tests.crate.http.router.get;

import trial.interfaces;

import trial.step;
import trial.runner;
import trial.discovery.spec;
import fluent.asserts;
import fluentasserts.vibe.request;


import vibe.data.json;
import vibe.http.router;

import crate.http.router;
import crate.policy.jsonapi;
import crate.policy.restapi;

import tests.crate.http.router.mocks;

Site getSite(string id) @safe {
  Site site;

  site._id = id;
  site.position = Point("Point", [1.5, 2.5]);

  return site;
}

void getSiteResponse(string id, HTTPServerResponse res) @safe {
  res.writeBody("hello", 200);
}

alias s = Spec!({
  describe("The crate router", {
    describe("with a GET REST API request", {
      it("should return the serialized structure", {
        auto router = new URLRouter();
        router.getWith!RestApi("/sites/:id", &getSite);

        auto element = Json.emptyObject;
        element["site"] = getSite("10").serializeToJson;

        request(router)
          .get("/sites/10")
            .expectStatusCode(200)
            .expectHeader("Content-Type", "application/json")
            .end((Response response) => {
              response.bodyJson.should.equal(element);
            });
      });

      it("should use the default route", {
        auto router = new URLRouter();
        router.getWith!RestApi(&getSite);

        request(router)
          .get("/sites/10")
            .expectStatusCode(200)
            .expectHeader("Content-Type", "application/json")
            .end();
      });

      it("should call a function with custom response", {
        auto router = new URLRouter();
        router.getWith!RestApi("/sites/:id", &getSiteResponse);

        request(router)
          .get("/sites/10")
            .expectStatusCode(200)
            .end((Response response) => {
              response.bodyString.should.equal("hello");
            });
      });

      it("should use the default route with custom response", {
        auto router = new URLRouter();
        router.getWith!(RestApi, Site)(&getSiteResponse);

        request(router)
          .get("/sites/10")
            .expectStatusCode(200)
            .end();
      });

    });

    describe("with a GET JSON API request", {
      it("should return the serialized structure", {
        auto router = new URLRouter();
        router.getWith!JsonApi("/sites/:id", &getSite);

        auto element = `{ "data": { "attributes": { "position": {
          "coordinates": [1.5, 2.5], "type": "Point" }},
          "relationships": {}, "type": "sites", "id": "10" }}`.parseJsonString;

        request(router)
          .get("/sites/10")
            .expectStatusCode(200)
            .expectHeader("Content-Type", "application/vnd.api+json")
            .end((Response response) => {
              response.bodyJson.should.equal(element);
            });
      });

      it("should call a function with custom response", {
        auto router = new URLRouter();
        router.getWith!JsonApi("/sites/:id", &getSiteResponse);

        request(router)
          .get("/sites/10")
            .expectStatusCode(200)
            .end((Response response) => {
              response.bodyString.should.equal("hello");
            });
      });
    });
  });
});