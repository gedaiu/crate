

module tests.crate.http.crateRouter.delete_;

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
    describe("with a DELETE REST Api request", {
      it("should delete one item", {
        request(queryRouter)
          .delete_("/sites/1")
            .expectStatusCode(204)
            .end();
      });

      it("should return 404 for unavailable items", {
        request(queryRouter)
          .delete_("/sites/24")
              .expectStatusCode(404)
              .end();
      });
    });
  });
});

