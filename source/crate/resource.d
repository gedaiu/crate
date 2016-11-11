module crate.resource;

public import vibe.core.stream;

import vibe.data.json;

interface CrateResource {
  string contentType();
  void write(OutputStream bodyWriter);
  ulong size();
}

version(unittest) {
  import crate.request;

  class TestResource : CrateResource {
    string contentType() {
      return "test/resource";
    }

    void write(OutputStream bodyWriter) {

    }

    ulong size() {
      return 0;
    }

    override string toString() const {
      return "test resource";
    }

    static TestResource fromString(string src) {
      return new TestResource;
    }
  }

  struct ResourceModel
	{
    string _id = "1";
    string name = "test";
		TestResource resource = new TestResource;
	}
}

@("access a model with resources")
unittest {
  import vibe.http.router;
  import crate.policy.restapi;
  import crate.http.router;
	import std.stdio;

	auto router = new URLRouter();
	auto resourceCrate = new TestCrate!ResourceModel;

	router
		.crateSetup
			.add(resourceCrate)
			.enableResource!(ResourceModel, "resource");

  request(router)
		.get("/resourcemodels/1")
			.expectStatusCode(200)
			.end((Response response) => {
        response.bodyString.writeln;
			});

  request(router)
		.get("/resourcemodels/1/resource")
			.expectStatusCode(200)
			.end((Response response) => {
        response.bodyString.writeln;
			});
}
