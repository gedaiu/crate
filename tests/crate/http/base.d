module tests.crate.base;

import std.datetime;

import trial.interfaces;
import trial.discovery.spec;

import fluent.asserts;
import fluentasserts.vibe.request;

import vibe.http.router;

import crate.base;

alias s = Spec!({
  describe("The applyFilters should call the any function if is defined", {
    URLRouter router;

    beforeEach({
      router = new URLRouter();
    });

    describe("any handler", {

      it("should call the any function if exists", {
        class AnyFilter {
          static string value;

          ICrateSelector any(HTTPServerRequest, ICrateSelector) {
            this.value = "ok";
            return null;
          }
        }

        void test(HTTPServerRequest req, HTTPServerResponse res) {
          ICrateSelector selector;
          selector.applyFilters(req, new AnyFilter);

          res.writeBody(AnyFilter.value);
        }
        
        router.get("*",  &test);

        request(router).get("/").end((Response response) => {
          response.bodyString.should.equal("ok");
        });
      });

      it("should accept missing any method", {
        class AnyFilter { }

        void test(HTTPServerRequest req, HTTPServerResponse res) {
          ICrateSelector selector;
          selector.applyFilters(req, new AnyFilter);

          res.writeBody("");
        }
        
        router.get("*",  &test);

        request(router).get("/").end((Response response) => {
          response.bodyString.should.equal("");
        });
      });

      it("should call only the selector method when the middleware any method is present", {
        class AnyFilter {
          static string value;

          void any(HTTPServerRequest req, HTTPServerResponse res) {
          }

          ICrateSelector any(HTTPServerRequest, ICrateSelector) {
            this.value = "ok";
            return null;
          }
        }

        void test(HTTPServerRequest req, HTTPServerResponse res) {
          ICrateSelector selector;
          selector.applyFilters(req, new AnyFilter);

          res.writeBody(AnyFilter.value);
        }
        
        router.get("*",  &test);

        request(router).get("/").end((Response response) => {
          response.bodyString.should.equal("ok");
        });
      });
    });

    describe("get handler", {
      class GetFilter {
        static string value;

        ICrateSelector get(HTTPServerRequest, ICrateSelector) {
          this.value = "ok";
          return null;
        }
      }
      
      it("should call the get function if exists", {
        void test(HTTPServerRequest req, HTTPServerResponse res) {
          ICrateSelector selector;
          selector.applyFilters(req, new GetFilter);

          res.writeBody(GetFilter.value);
        }

        router.get("*",  &test);

        request(router).get("/").end((Response response) => {
          response.bodyString.should.equal("ok");
        });
      });
    });


    describe("update handler", {
      class UpdateFilter {
        static string value;

        ICrateSelector update(HTTPServerRequest, ICrateSelector) {
          this.value = "ok";
          return null;
        }
      }
      
      it("should call the update function if exists", {
        void test(HTTPServerRequest req, HTTPServerResponse res) {
          ICrateSelector selector;
          selector.applyFilters(req, new UpdateFilter);

          res.writeBody(UpdateFilter.value);
        }

        router.post("*",  &test);

        request(router).post("/").end((Response response) => {
          response.bodyString.should.equal("ok");
        });
      });
    });
  });
});