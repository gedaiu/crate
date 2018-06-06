module tests.crate.http.crateRouter.middleware;


import tests.crate.http.crateRouter.mocks;

import vibe.http.router;

import trial.step;
import trial.runner;
import trial.discovery.spec;

import fluent.asserts;
import fluentasserts.vibe.request;
import fluentasserts.vibe.json;

import crate.http.router;
import crate.collection.memory;

class MockMiddleware {

  alias getList = this.handler;
  alias getItem = this.handler;
  alias create = this.handler;
  alias replace = this.handler;
  alias patch = this.handler;
  alias delete_ = this.handler;

  void handler(HTTPServerRequest req, HTTPServerResponse res) {
    res.statusCode = 412;
    res.writeBody("error");
  }
}


class MockAnyMiddleware {
  void any(HTTPServerRequest req, HTTPServerResponse res) {
    res.statusCode = 412;
    res.writeBody("error");
  }
}


alias s = Spec!({
  describe("The crate router", {
    URLRouter router;

    describe("with a middleware", {
      before({
        router = new URLRouter;
          auto baseCrate = new MemoryCrate!Site;

          router
            .crateSetup
              .add(baseCrate, [], new MockMiddleware);
      });

      it("should run the middleware handler for get list", {
        request(router)
          .get("/sites")
            .expectStatusCode(412)
            .end((Response response) => {
              response.bodyString.should.equal("error");
            });
      });

      it("should run the middleware handler for get item", {
        request(router)
          .get("/sites/123")
            .expectStatusCode(412)
            .end((Response response) => {
              response.bodyString.should.equal("error");
            });
      });

      it("should run the middleware handler for put item", {
        request(router)
          .put("/sites/123")
            .expectStatusCode(412)
            .end((Response response) => {
              response.bodyString.should.equal("error");
            });
      });

      it("should run the middleware handler for patch item", {
        request(router)
          .patch("/sites/123")
            .expectStatusCode(412)
            .end((Response response) => {
              response.bodyString.should.equal("error");
            });
      });

      it("should run the middleware handler for patch item", {
        request(router)
          .delete_("/sites/123")
            .expectStatusCode(412)
            .end((Response response) => {
              response.bodyString.should.equal("error");
            });
      });

      it("should run the middleware handler for post item", {
        request(router)
          .post("/sites")
            .expectStatusCode(412)
            .end((Response response) => {
              response.bodyString.should.equal("error");
            });
      });
    });

    describe("with an empty middleware", {
      before({
        router = new URLRouter;
          auto baseCrate = new MemoryCrate!Site;

          router
            .crateSetup
              .add(baseCrate, [], new Object);
      });

      it("should run the middleware handler for get list", {
        request(router)
          .get("/sites")
            .expectStatusCode(200)
            .end;
      });

      it("should run the middleware handler for get item", {
        request(router)
          .get("/sites/123")
            .expectStatusCode(404)
            .end;
      });

      it("should run the middleware handler for put item", {
        request(router)
          .put("/sites/123")
            .expectStatusCode(400)
            .end;
      });

      it("should run the middleware handler for patch item", {
        request(router)
          .patch("/sites/123")
            .expectStatusCode(404)
            .end;
      });

      it("should run the middleware handler for patch item", {
        request(router)
          .delete_("/sites/123")
            .expectStatusCode(404)
            .end;
      });

      it("should run the middleware handler for post item", {
        request(router)
          .post("/sites")
            .expectStatusCode(400)
            .end;
      });
    });

    describe("with a middleware with the `any` method", {
      before({
        router = new URLRouter;
          auto baseCrate = new MemoryCrate!Site;

          router
            .crateSetup
              .add(baseCrate, [], new MockAnyMiddleware);
      });

      it("should run the middleware handler for get list", {
        request(router)
          .get("/sites")
            .expectStatusCode(412)
            .end((Response response) => {
              response.bodyString.should.equal("error");
            });
      });

      it("should run the middleware handler for get item", {
        request(router)
          .get("/sites/123")
            .expectStatusCode(412)
            .end((Response response) => {
              response.bodyString.should.equal("error");
            });
      });

      it("should run the middleware handler for put item", {
        request(router)
          .put("/sites/123")
            .expectStatusCode(412)
            .end((Response response) => {
              response.bodyString.should.equal("error");
            });
      });

      it("should run the middleware handler for patch item", {
        request(router)
          .patch("/sites/123")
            .expectStatusCode(412)
            .end((Response response) => {
              response.bodyString.should.equal("error");
            });
      });

      it("should run the middleware handler for patch item", {
        request(router)
          .delete_("/sites/123")
            .expectStatusCode(412)
            .end((Response response) => {
              response.bodyString.should.equal("error");
            });
      });

      it("should run the middleware handler for post item", {
        request(router)
          .post("/sites")
            .expectStatusCode(412)
            .end((Response response) => {
              response.bodyString.should.equal("error");
            });
      });
    });
  });
});

