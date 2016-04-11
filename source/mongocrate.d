module crate.mongo;

import crate.base;

import vibe.inet.url;
import vibe.http.router;
import vibe.data.json;
import vibe.db.mongo.collection;

class MongoCrate : BaseCrate {

  this(URLRouter router) {
    super(router);
  }
}

version(unittest) {
  import crate.request;

	struct NewTestModel {
		string name;
	}

	struct TestModel {
		ulong id = 1;
		string name = "";
	}
}

unittest {
	auto router = new URLRouter();
	auto crate = new MongoCrate(router);

	request(router)
		.post("/testModels")
			.send(NewTestModel("test model"))

			//.expectHeader("Content-Type", "application/vnd.api+json")
			//.expectHeaderContains("Location", "http://localhost/testModels/")
			.expectStatusCode(201)

			.end((Response response) => {
        std.stdio.writeln(response.bodyString);
			});
}
