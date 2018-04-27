module tests.crate.http.router.delete_;

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

void deleteSiteWithResponse(string id, HTTPServerResponse res) @safe { 
  res.statusCode = 204;
  res.writeBody("");
}

void deleteSite(string id) @safe { 
}

alias s = Spec!({
  describe("The crate router", {
    
    describe("with a DELETE request", {
      it("should accept a valid request with id", {
        auto router = new URLRouter();
        router.deleteWith!(RestApi, Site)(&deleteSiteWithResponse);

        request(router)
          .delete_("/sites/122")
            .expectHeader("Access-Control-Allow-Origin", "*")
            .expectHeader("Access-Control-Request-Method", "DELETE")
            .expectStatusCode(204)
            .end((Response response) => {
              response.bodyString.should.equal("");
            });
      });

      it("should accept a valid request with id when the response is not handeled", {
        auto router = new URLRouter();
        router.deleteWith!(RestApi, Site)(&deleteSite);

        request(router)
          .delete_("/sites/122")
            .expectStatusCode(204)
            .expectHeader("Access-Control-Allow-Origin", "*")
            .expectHeader("Access-Control-Request-Method", "DELETE")
            .end((Response response) => {
              response.bodyString.should.equal("");
            });
      });
    });

  });
});