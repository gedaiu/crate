module tests.crate.http.router.actions;

import trial.interfaces;

import trial.step;
import trial.runner;
import trial.discovery.spec;
import fluent.asserts;
import fluentasserts.vibe.request;


import vibe.data.json;
import vibe.http.router;

import crate.http.router;
import crate.http.handlers.action;
import crate.policy.jsonapi;
import crate.policy.restapi;

import tests.crate.http.router.mocks;

struct MockModel {
  @optional string _id = "1";
  string name = "";

  void actionChange() {
    name = "changed";
  }

  void actionParam(string data) {
    name = data;
  }

  string actionChangeAndReturn() {
    name = "changed and return";

    return name;
  }

  string actionParamAndReturn(string data) {
    name = data;

    return name;
  }
}

MockModel getMockModel(string id) @safe {
  return MockModel();
}

Json lastMockItem;

Json setMockModel(Json item) @safe {
  lastMockItem = item;
  return item;
}

alias s = Spec!({
  describe("The crate router", {
    describe("with a REST API action request", {
      it("should call a method structure and return the result", {
        auto router = new URLRouter();
        router.enableAction!(RestApi, MockModel, "actionChangeAndReturn")(&getMockModel);

        request(router)
          .get("/mockmodels/10/actionChangeAndReturn")
            .expectStatusCode(200)
            .expectHeader("Content-Type", "text/plain; charset=UTF-8")
            .expectHeader("Access-Control-Allow-Origin", "*")
            .expectHeader("Access-Control-Allow-Methods", "OPTIONS, GET")
            .end((Response response) => {
              response.bodyString.should.equal("changed and return");
            });
      });

      it("should call a method structure with a string parameter and return the result", {
        auto router = new URLRouter();
        router.enableAction!(RestApi, MockModel, "actionParamAndReturn")(&getMockModel);

        request(router)
          .post("/mockmodels/10/actionParamAndReturn")
            .send("test message")
              .expectStatusCode(200)
              .expectHeader("Content-Type", "text/plain; charset=UTF-8")
              .expectHeader("Access-Control-Allow-Origin", "*")
              .expectHeader("Access-Control-Allow-Methods", "OPTIONS, POST")
              .end((Response response) => {
                response.bodyString.should.equal("test message");
              });
      });

      it("should call a method structure, return the result and update the crate", {
        auto router = new URLRouter();
        router.enableAction!(RestApi, MockModel, "actionChangeAndReturn")(&getMockModel, &setMockModel);

        request(router)
          .get("/mockmodels/10/actionChangeAndReturn")
            .expectStatusCode(200)
            .expectHeader("Content-Type", "text/plain; charset=UTF-8")
            .expectHeader("Access-Control-Allow-Origin", "*")
            .expectHeader("Access-Control-Allow-Methods", "OPTIONS, GET")
            .end((Response response) => {
              response.bodyString.should.equal("changed and return");
              lastMockItem.should.equal(`{ "_id": "1", "name": "changed and return" }`.parseJsonString);
            });
      });
    });
  });
});