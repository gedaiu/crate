module tests.crate.http.crateRouter.mocks;

import crate.base;
import crate.collection.memory;
import crate.http.router;
import vibe.data.json;
import vibe.http.router;
import fluentasserts.vibe.request;
import std.algorithm;


public import tests.crate.http.mocks;

class TypeFilter : ICrateFilter {
  ICrateSelector apply(HTTPServerRequest request, ICrateSelector selector) {
    if("type" !in request.query) {
      return selector;
    }

    return selector.where("position.type", request.query["type"]);
  }
}

class SomeTestCrateFilter : ICrateFilter {
  ICrateSelector apply(HTTPServerRequest request, ICrateSelector selector) {
    return new CrateRange(selector.exec.filter!(a => a["position"]["type"] == "Point"));
  }
}

auto queryRouter() {
  auto router = new URLRouter();
  auto baseCrate = new MemoryCrate!Site;

  router
    .crateSetup
      .add(baseCrate, new SomeTestCrateFilter);

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

  return router;
}

auto testRouter() {
  auto router = new URLRouter();
  auto baseCrate = new MemoryCrate!Site;

  router
    .crateSetup
      .add(baseCrate);

  Json data = `{
      "position": {
        "type": "Point",
        "coordinates": [0, 0]
      }
  }`.parseJsonString;

  baseCrate.addItem(data);

  return request(router);
}