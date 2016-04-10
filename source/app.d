import std.stdio;

import vibe.inet.url;
import vibe.http.router;
import vibe.data.json;

import crate.request;

enum CrateAccess {
	getList,
	getItem,

	addItem,
	deleteItem,
	editItem
}

class CrateManager {
	this(URLRouter router) {
		router.post("/testModels", &addItem);
	}

	void addItem(HTTPServerRequest request, HTTPServerResponse response) {
		response.statusCode = 201;
		response.headers["Content-Type"] = "application/vnd.api+json";
		response.headers["Location"] = "http://localhost/testModels/";
	}
}

version(unittest) {
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
	auto crate = new CrateManager(router);

	request(router)
		.post("/testModels")
			.send(NewTestModel("test model"))

			.expectHeader("Content-Type", "application/vnd.api+json")
			.expectHeaderContains("Location", "http://localhost/testModels/")
			.expectStatusCode(201)

			.end((HTTPServerResponse response) => {
				std.stdio.writeln("===>", response.statusCode);
				assert(response.statusCode == 201);
			});
}
