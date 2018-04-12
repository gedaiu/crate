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
        router.deleteWith!RestApi("/sites/:id", &deleteSiteWithResponse);

        request(router)
          .delete_("/sites/122")
            .expectStatusCode(204)
            .end((Response response) => {
              response.bodyString.should.equal("");
            });
      });

      it("should use the default route when it is missing for a handler with response", {
        auto router = new URLRouter();
        router.deleteWith!(RestApi, Site)(&deleteSiteWithResponse);

        request(router)
          .delete_("/sites/122")
            .expectStatusCode(204)
            .end();
      });


      it("should use the default route when it is missing for a handler with no response", {
        auto router = new URLRouter();
        router.deleteWith!(RestApi, Site)(&deleteSite);

        request(router)
          .delete_("/sites/122")
            .expectStatusCode(204)
            .end();
      });

      it("should accept a valid request with id when the response is not handeled", {
        auto router = new URLRouter();
        router.deleteWith!RestApi("/sites/:id", &deleteSite);

        request(router)
          .delete_("/sites/122")
            .expectStatusCode(204)
            .end((Response response) => {
              response.bodyString.should.equal("");
            });
      });

       it("should throw an exception on invalid route name", {
        auto router = new URLRouter();
        ({
          router.deleteWith!RestApi("/sites/:_id", &deleteSite);
        }).should.throwAnyException.withMessage("Invalid `/sites/:_id` route. It must end with `/:id`.");
      });
    });

  });
});