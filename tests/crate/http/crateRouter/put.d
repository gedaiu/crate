

module tests.crate.http.crateRouter.put;

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
    describe("with a PUT REST Api request", {
      it("it should replace one item using REST API", {
        auto data = `{
          "site": {
            "position": {
              "type": "Point",
              "coordinates": [0, 1]
            }
          }
        }`.parseJsonString;

        testRouter
          .put("/sites/1")
            .send(data)
              .expectStatusCode(200)
              .end((Response response) => {
                data["site"]["_id"] = "1";
                response.bodyJson.should.equal(data);
              });
      });


      it("should replace available items using query alteration", {
        Json dataUpdate = `{ "site": {
            "position": {
              "type": "Point",
              "coordinates": [0, 0]
            }
        }}`.parseJsonString;

        request(queryRouter)
          .put("/sites/1")
            .send(dataUpdate)
              .expectStatusCode(200)
              .end();
      });

      it("should replace a missing resource", {
        Json dataUpdate = `{ "site": {
            "position": {
              "type": "Point",
              "coordinates": [0, 0]
            }
        }}`.parseJsonString;

        request(queryRouter)
          .put("/sites/24")
            .send(dataUpdate)
              .expectStatusCode(404)
              .end();
      });
    });
  });
});

