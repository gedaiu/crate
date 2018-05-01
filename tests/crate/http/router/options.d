module tests.crate.http.router.options;

import trial.interfaces;

import trial.step;
import trial.runner;
import trial.discovery.spec;
import fluent.asserts;
import fluentasserts.vibe.request;


import vibe.data.json;
import vibe.inet.url;
import vibe.http.router;

import crate.http.router;
import crate.policy.jsonapi;
import crate.policy.restapi;

import tests.crate.http.router.mocks;

Site postSite(Site site) @safe {
  site._id = "122";
  return site;
}

alias s = Spec!({
  describe("The crate router", {
    describe("with a OPTIONS request", {
      it("should get the access control headers", {
        auto router = new URLRouter();
        router.postWith!RestApi(&postSite);

        Json dataUpdate = restSiteFixture.parseJsonString;

        request(router)
          .customMethod!(HTTPMethod.OPTIONS)(URL("http://localhost/sites"))
            .send(dataUpdate)
              .expectStatusCode(200)
              .expectHeader("Access-Control-Allow-Origin", "*")
              .expectHeader("Access-Control-Allow-Methods", "OPTIONS, POST")
              .end;
      });
    });
  });
});