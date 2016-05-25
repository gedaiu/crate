import vibe.d;

import crate.mongo;
import crate.router;
import crate.generator.openapi;
import std.stdio;

struct Comment {
	BsonObjectID userId;
	string message;
}

@("plural:Categories")
struct Category {
	BsonObjectID _id;

	string name;
	string color;
}

struct Book
{
	@optional {
		BsonObjectID _id;
	}

	string name;
	string author;
	Category category;

	@optional
	int something;

	double price;
	bool inStock;

	@optional
	Comment[] comments;

	void action()
	{
		inStock = false;
	}

	string actionResponse()
	{
		return inStock ? "ok." : "not ok.";
	}
}

shared static this()
{
	auto settings = new HTTPServerSettings;
	settings.port = 9090;
	settings.options = HTTPServerOption.parseQueryString
		| HTTPServerOption.parseFormBody | HTTPServerOption.parseJsonBody;

	auto client = connectMongoDB("127.0.0.1");

	auto router = new URLRouter;

	auto collection = client.getCollection("test.books");

	auto crate = new MongoCrate(collection);
	auto crateRouter = new CrateRouter!Book(router, crate);
	crateRouter.enableAction!"action";
	crateRouter.enableAction!"actionResponse";

	crateRouter.generateOpenApi;

	listenHTTP(settings, router);
}

void generateOpenApi(T)(T crateRouter)
{
	auto api = crateRouter.toOpenApi;

	auto f = File("openApi.json", "w");

	f.write(api.serializeToJson.toPrettyString);
}
