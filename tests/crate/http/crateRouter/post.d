module tests.crate.http.crateRouter.post;

import trial.interfaces;

import trial.step;
import trial.runner;
import trial.discovery.spec;
import fluent.asserts;
import fluentasserts.vibe.request;


import vibe.data.json;
import vibe.http.router;

import crate.http.router;
import crate.api.json.policy;
import crate.api.rest.policy;
import crate.collection.memory;

import tests.crate.http.router.mocks;

struct ChildValue {
  @optional string _id;
  string value;
}

struct ParentValue {
  @optional string _id;
  ChildValue value;
}

struct OtherParentValue {
  @optional string _id;
  ChildValue[] values;
}

alias s = Spec!({
  describe("The crate router", {
    describe("with a POST REST Api request", {
      URLRouter router;
      Json data;

      describe("for a structure with a relation", {
        before({
          router = new URLRouter();

          auto parentCrate = new MemoryCrate!ParentValue;
          auto childCrate = new MemoryCrate!ChildValue;

          childCrate.addItem(ChildValue("1").serializeToJson);

          router
            .crateSetup
              .add(parentCrate)
              .add(childCrate);
        });

        it("should work with referenced child values", {
          data = `{ "parentValue": {
            "value": "1"
          }}`.parseJsonString;
          request(router)
            .post("/parentvalues")
              .send(data)
                .expectStatusCode(201)
                .expectHeader("Content-Type", "application/json")
                .end((Response response) => {
                  response.bodyJson.should.equal(`{"parentValue": {"_id": "1", "value": "1"}}`.parseJsonString);
                });
        });


        it("should respond with 400 with with an object relation", {
          data = `{ "parentValue": {
            "value": {}
          }}`.parseJsonString;
          request(router)
            .post("/parentvalues")
              .send(data)
                .expectStatusCode(400)
                .expectHeader("Content-Type", "application/json; charset=UTF-8")
                .expectHeader("Access-Control-Allow-Origin", "*")
                .expectHeader("Access-Control-Allow-Methods", "OPTIONS, POST, GET")
                .end((Response response) => {
                  response.bodyJson.should.equal("{
                    \"errors\": [
                      {
                        \"description\": \"`value` is a relation and it should contain an id.\",
                        \"title\": \"Validation error\",
                        \"status\": 400
                      }
                    ]
                  }".parseJsonString);
                });
        });
      });

      describe("for a structure with an array of relations", {
        before({
          router = new URLRouter();

          auto parentCrate = new MemoryCrate!OtherParentValue;
          auto childCrate = new MemoryCrate!ChildValue;

          childCrate.addItem(ChildValue("1").serializeToJson);

          router
            .crateSetup
              .add(parentCrate)
              .add(childCrate);
        });

        it("should work with referenced child values", {
          data = `{ "otherParentValue": {
            "values": ["1"]
          }}`.parseJsonString;
          request(router)
            .post("/otherparentvalues")
              .send(data)
                .expectStatusCode(201)
                .expectHeader("Content-Type", "application/json")
                .end((Response response) => {
                  response.bodyJson.should.equal(`{"otherParentValue": {"_id": "1", "values": ["1"]}}`.parseJsonString);
                });
        });
      });
    });
  });
});