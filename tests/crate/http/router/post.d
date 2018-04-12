module tests.crate.http.router.post;

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

Site postSite(Site site) @safe {
  site._id = "122";
  return site;
}

Json postJsonSite(Site site) @safe {
  site._id = "122";
  return site.serializeToJson;
}

void postVoidSite(Site site, HTTPServerResponse res) @safe {
  res.statusCode = 204;
  res.writeVoidBody();
}

alias s = Spec!({
  describe("The crate router", {
    describe("with a POST REST Api request", {
      it("should accept a valid request", {
        auto router = new URLRouter();
        router.postWith!RestApi("/sites", &postSite);

        Json dataUpdate = restSiteFixture.parseJsonString;

        request(router)
          .post("/sites")
            .send(dataUpdate)
              .expectStatusCode(200)
              .expectHeader("Content-Type", "application/json")
              .end((Response response) => {
                dataUpdate["site"]["_id"] = "122";
                response.bodyJson.should.equal(dataUpdate);
              });
      });

      it("should deduce the post route", {
        auto router = new URLRouter();
        router.postWith!RestApi(&postSite);

        Json dataUpdate = restSiteFixture.parseJsonString;

        request(router)
          .post("/sites")
            .send(dataUpdate)
              .expectStatusCode(200)
              .expectHeader("Content-Type", "application/json")
              .end((Response response) => {
                dataUpdate["site"]["_id"] = "122";
                response.bodyJson.should.equal(dataUpdate);
              });
      });

      it("should accept a valid request", {
        auto router = new URLRouter();
        router.postWith!RestApi("/sites", &postJsonSite);

        Json dataUpdate = restSiteFixture.parseJsonString;

        request(router)
          .post("/sites")
            .send(dataUpdate)
              .expectStatusCode(200)
              .expectHeader("Content-Type", "application/json")
              .end((Response response) => {
                dataUpdate["site"]["_id"] = "122";
                response.bodyJson.should.equal(dataUpdate);
              });
      });

      it("should accept a valid request and return an empty body", {
        auto router = new URLRouter();
        router.postWith!RestApi("/sites", &postVoidSite);

        Json dataUpdate = restSiteFixture.parseJsonString;

        request(router)
          .post("/sites")
            .send(dataUpdate)
              .expectStatusCode(204)
              .end((Response response) => {
                response.bodyString.should.equal("");
              });
      });


      it("should deduce the route of a post with result", {
        auto router = new URLRouter();
        router.postWith!RestApi(&postVoidSite);

        Json dataUpdate = restSiteFixture.parseJsonString;

        request(router)
          .post("/sites")
            .send(dataUpdate)
              .expectStatusCode(204)
              .end;
      });

      it("should respond with an error when there are missing fields", {
        auto router = new URLRouter();
        router.postWith!RestApi("/sites", &postSite);

        auto dataUpdate = `{ "site": { }}`.parseJsonString;
        auto expectedError = `{"errors": [{
          "description": "Can not deserialize data. Got .site.position of type undefined, expected object.", 
          "title": "Validation error", 
          "status": 400 }]}`.parseJsonString;

        request(router)
          .post("/sites")
            .send(dataUpdate)
              .expectStatusCode(400)
              .expectHeader("Content-Type", "application/json; charset=UTF-8")
              .end((Response response) => {
                response.bodyJson.should.equal(expectedError);
              });
      });
    });
  });
});