import vibe.d;

import crate.mongo;
import crate.router;

struct TestModel
{
	@optional {
		string _id;
		string other = "";
	}

	string name = "";

	void action() {}

	string actionResponse() {
		return "ok.";
	}
}


shared static this() {
	auto settings = new HTTPServerSettings;
	settings.port = 9090;
	settings.options = HTTPServerOption.parseQueryString |
		HTTPServerOption.parseFormBody |
		HTTPServerOption.parseJsonBody;

	auto client = connectMongoDB("127.0.0.1");

	auto router = new URLRouter;

	auto collection = client.getCollection("test.model");
	collection.drop;

	auto crate = new MongoCrate!TestModel(collection);
	auto crateRouter = new CrateRouter!TestModel(router, crate);
	crateRouter.enableAction!"actionResponse";

	listenHTTP(settings, router);
}
