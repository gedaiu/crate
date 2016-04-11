module crate.base;

import vibe.inet.url;
import vibe.http.router;
import vibe.data.json;

enum CrateAccess {
	getList,
	getItem,

	addItem,
	deleteItem,
	editItem
}

class BaseCrate {
	this(URLRouter router) {
		router.post("/testModels", &addItem);
	}

	void addItem(HTTPServerRequest request, HTTPServerResponse response) {
		response.statusCode = 201;
		response.headers["Content-Type"] = "application/vnd.api+json";
		response.headers["Location"] = "http://localhost/testModels/";

		response.writeVoidBody();
	}
}
