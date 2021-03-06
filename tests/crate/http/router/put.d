module tests.crate.http.router.put;


import trial.interfaces;
import tests.crate.http.router.mocks;

import trial.step;
import trial.runner;
import trial.discovery.spec;
import fluent.asserts;
import fluentasserts.vibe.request;

import vibe.data.json;
import vibe.http.router;

import crate.http.router;
import crate.http.handlers.put;
import crate.api.json.policy;
import crate.api.rest.policy;

Site putSite(Site site) @safe {
  return site;
}

void putVoidSite(Site site, HTTPServerResponse res) @safe {
  res.statusCode = 204;
  res.writeVoidBody;
}

Json putJsonSite(Site site) @safe {
  return site.serializeToJson;
}

void putVoidJsonSite(Json site) @safe {
}

Site putSiteJson(Json site) @safe {
  return Site("10", Point("Point", [0, 0]));
}

alias s = Spec!({
  describe("The crate router", {
    describe("with a PUT REST Api request", {
      it("should accept a valid request and return the changed data", {
        auto router = new URLRouter();
        auto putOperation = new PutOperation!(RestApi, Site)(router);
        putOperation.handler = &putSite;
        putOperation.bind;
        

        Json dataUpdate = restSiteFixture.parseJsonString;

        request(router)
          .put("/sites/10")
            .send(dataUpdate)
              .expectStatusCode(200)
              .expectHeader("Content-Type", "application/json")
              .expectHeader("Access-Control-Allow-Origin", "*")
              .expectHeader("Access-Control-Allow-Methods", "OPTIONS, PUT")
              .end((Response response) => {
                dataUpdate["site"]["_id"] = "10";
                response.bodyJson.should.equal(dataUpdate);
              });
      });

      it("should accept a valid request and return the changed data", {
        auto router = new URLRouter();
        auto putOperation = new PutOperation!(RestApi, Site)(router);
        putOperation.handler = &putVoidJsonSite;
        putOperation.bind;

        Json dataUpdate = restSiteFixture.parseJsonString;

        request(router)
          .put("/sites/10")
            .send(dataUpdate)
              .expectStatusCode(200)
              .expectHeader("Access-Control-Allow-Origin", "*")
              .expectHeader("Access-Control-Allow-Methods", "OPTIONS, PUT")
              .end((Response response) => {
                response.bodyString.should.equal("");
              });
      });

      it("should accept a valid request and return the changed data", {
        auto router = new URLRouter();
        auto putOperation = new PutOperation!(RestApi, Site)(router);
        putOperation.handler = &putSiteJson;
        putOperation.bind;

        Json dataUpdate = restSiteFixture.parseJsonString;

        request(router)
          .put("/sites/10")
            .send(dataUpdate)
              .expectStatusCode(200)
              .expectHeader("Access-Control-Allow-Origin", "*")
              .expectHeader("Access-Control-Allow-Methods", "OPTIONS, PUT")
              .end((Response response) => {
                dataUpdate["site"]["_id"] = "10";
                response.bodyJson.should.equal(dataUpdate);
              });
      });

      it("should accept a valid request and return an empty body", {
        auto router = new URLRouter();
        auto putOperation = new PutOperation!(RestApi, Site)(router);
        putOperation.handler = &putVoidSite;
        putOperation.bind;

        Json dataUpdate = restSiteFixture.parseJsonString;

        request(router)
          .put("/sites/10")
            .send(dataUpdate)
              .expectStatusCode(204)
              .expectHeader("Access-Control-Allow-Origin", "*")
              .expectHeader("Access-Control-Allow-Methods", "OPTIONS, PUT")
              .end((Response response) => {
                response.bodyString.should.equal("");
              });
      });

      it("should accept a valid request as json", {
        auto router = new URLRouter();
        auto putOperation = new PutOperation!(RestApi, Site)(router);
        putOperation.handler = &putJsonSite;
        putOperation.bind;

        Json dataUpdate = restSiteFixture.parseJsonString;

        request(router)
          .put("/sites/10")
            .send(dataUpdate)
              .expectStatusCode(200)
              .expectHeader("Access-Control-Allow-Origin", "*")
              .expectHeader("Access-Control-Allow-Methods", "OPTIONS, PUT")
              .end((Response response) => {
                dataUpdate["site"]["_id"] = "10";
                response.bodyJson.should.equal(dataUpdate);
              });
      });

      it("should respond with an error when there are missing fields", {
        auto router = new URLRouter();
        auto putOperation = new PutOperation!(RestApi, Site)(router);
        putOperation.handler = &putSite;
        putOperation.bind;

        auto dataUpdate = `{ "site": { }}`.parseJsonString;
        auto expectedError = "{\"errors\": [{
          \"description\": \"`position` is missing\", 
          \"title\": \"Validation error\", 
          \"status\": 400 }]}".parseJsonString;

        request(router)
          .put("/sites/10")
            .send(dataUpdate)
              .expectStatusCode(400)
              .expectHeader("Access-Control-Allow-Origin", "*")
              .expectHeader("Access-Control-Allow-Methods", "OPTIONS, PUT")
              .expectHeader("Content-Type", "application/json; charset=UTF-8")
              .end((Response response) => {
                response.bodyJson.should.equal(expectedError);
              });
      });
    });

    describe("with a PUT JSON Api request", {
      it("should accept a valid request", {
        auto router = new URLRouter();
        auto putOperation = new PutOperation!(JsonApi, Site)(router);
        putOperation.handler = &putSite;
        putOperation.bind;

        Json dataUpdate = jsonSiteFixture.parseJsonString;

        request(router)
          .put("/sites/10")
            .send(dataUpdate)
              .expectStatusCode(200)
              .expectHeader("Access-Control-Allow-Origin", "*")
              .expectHeader("Access-Control-Allow-Methods", "OPTIONS, PUT")
              .expectHeader("Content-Type", "application/vnd.api+json")
              .end((Response response) => {
                dataUpdate["data"]["id"] = "10";
                dataUpdate["data"]["relationships"] = Json.emptyObject;

                response.bodyJson.should.equal(dataUpdate);
              });
      });

      it("should respond with an error when there are missing fields", {
        auto router = new URLRouter();
        auto putOperation = new PutOperation!(JsonApi, Site)(router);
        putOperation.handler = &putSite;
        putOperation.bind;

        Json dataUpdate = `{ "data": {
          "type": "sites",
          "attributes": {
          }}}`.parseJsonString;

        auto expectedError = "{\"errors\": [{
          \"description\": \"`position` is missing\",  
          \"title\": \"Validation error\", 
          \"status\": 400 }]}".parseJsonString;

        request(router)
          .put("/sites/10")
            .send(dataUpdate)
              .expectStatusCode(400)
              .expectHeader("Access-Control-Allow-Origin", "*")
              .expectHeader("Access-Control-Allow-Methods", "OPTIONS, PUT")
              .expectHeader("Content-Type", "application/json; charset=UTF-8")
              .end((Response response) => {
                response.bodyJson.should.equal(expectedError);
              });
      });
    });
  });
});