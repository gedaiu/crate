module tests.crate.http.crateRouter.oauth;

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

import vibeauth.client;
import vibeauth.users;
import vibeauth.router.oauth;

import std.datetime;

alias s = Spec!({
  describe("The crate router", {
    describe("with oauth", {
      URLRouter router;
      MemoryCrate!Site baseCrate;

      before({
        router = new URLRouter();
        baseCrate = new MemoryCrate!Site;

        auto collection = new UserMemmoryCollection(["doStuff"]);
        auto user = new User("user@gmail.com", "password");
        user.name = "John Doe";
        user.username = "test";
        user.id = 1;

        collection.add(user);

        auto refreshToken = collection.createToken("user@gmail.com", Clock.currTime + 3600.seconds, ["doStuff", "refresh"], "Refresh");

        auto client = new Client();
        client.id = "CLIENT_ID";

        auto clientCollection = new ClientCollection([ client ]);
        auto auth = new OAuth2(collection, clientCollection);

        router
          .crateSetup
            .enable(auth)
            .add(baseCrate);
      });

      it("should add the token route", {
        auto testRouter = request(router);

        testRouter.get("/auth/token")
          .expectStatusCode(401)
          .end();
      });

      it("should add the authorize route", {
        auto testRouter = request(router);

        testRouter.get("/auth/authorize")
          .expectStatusCode(400)
          .end();
      });

      it("should add the authenticate route", {
        auto testRouter = request(router);

        testRouter.get("/auth/authenticate")
          .expectStatusCode(400)
          .end();
      });

      it("should add the revoke route", {
        auto testRouter = request(router);

        testRouter.post("/auth/revoke")
          .expectStatusCode(400)
          .end((Response response) => {
            import std.stdio;
            writeln(response.bodyString);
          });
      });
    });
  });
});
