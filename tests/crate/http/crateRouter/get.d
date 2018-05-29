module tests.crate.http.crateRouter.get;

import tests.crate.http.crateRouter.mocks;

import trial.interfaces;

import trial.step;
import trial.runner;
import trial.discovery.spec;
import fluent.asserts;
import fluentasserts.vibe.request;
import fluentasserts.vibe.json;

import vibe.data.json;
import vibe.http.router;

import crate.http.router;
import crate.collection.memory;


alias s = Spec!({
  describe("The crate router", {
    describe("with a GET REST Api request", {
      it("should get data with a query", {
          auto router = new URLRouter();
          auto baseCrate = new MemoryCrate!Site;

          router
            .crateSetup
              .add(baseCrate, [ new TypeFilter ]);

          Json data1 = `{
              "position": {
                "type": "Point",
                "coordinates": [0, 0]
              }
          }`.parseJsonString;

          Json data2 = `{
              "position": {
                "type": "Dot",
                "coordinates": [1, 1]
              }
          }`.parseJsonString;

          baseCrate.addItem(data1);
          baseCrate.addItem(data2);

          request(router)
            .get("/sites?type=Point")
              .expectStatusCode(200)
              .end((Response response) => {
                response.bodyJson["sites"].length.should.equal(1);
                response.bodyJson["sites"][0]["_id"].to!string.should.equal("1");
              });

      });

      it("should GET all items using REST API", {
        testRouter
          .get("/sites")
            .expectStatusCode(200)
            .end((Response response) => {
              response.bodyJson["sites"].length.should.be.greaterThan(0);
              response.bodyJson["sites"][0]["_id"].to!string.should.equal("1");
            });
      });

      it("should GET one item using REST API", {
        testRouter
          .get("/sites/1")
            .expectStatusCode(200)
            .end((Response response) => {
              response.bodyJson.keys.should.equal(["site"]);
              response.bodyJson["site"].keys.should.contain(["position", "_id"]);
              response.bodyJson["site"]["_id"].to!string.should.equal("1");
            });
      });

      it("should get all items using query alteration", {
        request(queryRouter)
          .get("/sites")
            .expectStatusCode(200)
            .end((Response response) => {
              response.bodyJson["sites"].length.should.equal(1);
            });
      });

      it("should get available items with query alteration", {
        request(queryRouter)
          .get("/sites/1")
            .expectStatusCode(200)
            .end((Response response) => {
              response.bodyJson["site"]["_id"].to!string.should.equal("1");
            });
      });

      it("should get unavailable items with query alteration", {
        request(queryRouter)
          .get("/sites/22")
            .expectStatusCode(404)
            .end();
      });
    });
  });
});

