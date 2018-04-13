module tests.crate.http.router.get_list;

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

Site[] getListSites() @safe {
  return [ getSite("1") ];
}

void getSiteResponse(string id, HTTPServerResponse res) @safe {
  res.writeBody("hello", 200);
}

alias s = Spec!({
  describe("The crate router", {

    describe("with a GET All elements using REST API request", {
      it("should return the serialized structure", {
        auto router = new URLRouter();
        router.getListWith!RestApi("/sites", &getListSites);

        auto elements = `{"sites":[{"_id":"1","position":{"coordinates":[1.5,2.5],"type":"Point"}}]}`.parseJsonString;

        request(router)
          .get("/sites")
            .expectStatusCode(200)
            .expectHeader("Content-Type", "application/json")
            .end((Response response) => {
              response.bodyJson.should.equal(elements);
            });
      });

      it("should return use the default route", {
        auto router = new URLRouter();
        router.getListWith!RestApi(&getListSites);

        request(router)
          .get("/sites")
            .expectStatusCode(200)
            .expectHeader("Content-Type", "application/json")
            .end();
      });
    });

    describe("with a GET All elements using JSON API request", {
      it("should return the serialized structure", {
        auto router = new URLRouter();
        router.getListWith!JsonApi("/sites", &getListSites);

        auto elements = `{"data": [
          {"attributes": { "position": { "coordinates": [ 1.5, 2.5 ], "type": "Point"} },
           "relationships": {}, "type": "sites", "id": "1" } ]}`.parseJsonString;

        request(router)
          .get("/sites")
            .expectStatusCode(200)
            .expectHeader("Content-Type", "application/vnd.api+json")
            .end((Response response) => {
              response.bodyJson.should.equal(elements);
            });
      });
    });

  });
});