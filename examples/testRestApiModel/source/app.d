import vibe.d;

import crate.mongo;
import crate.router;
import crate.generator.openapi;
import crate.generator.ember;
import crate.api.rest.policy;
import std.stdio;

struct Comment {
	ObjectID userId;
	string message;
}

@("plural:Categories")
struct Category {
	ObjectID _id;

	string name;
	string color;
}

struct Book
{
	@optional {
		ObjectID _id;
	}

	string name;
	string author;
	Category[] category;

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

	auto bookCollection = client.getCollection("test.books");
	auto categoryCollection = client.getCollection("test.bookCategories");

	auto bookCrate = new MongoCrate!Book(bookCollection);
	auto categoryCrate = new MongoCrate!Category(categoryCollection);

	auto policy = new const CrateRestApiPolicy();

	auto crateRouter = new CrateRouter(router, policy, bookCrate, categoryCrate);
	crateRouter.enableAction!(Book, "action");
	crateRouter.enableAction!(Book, "actionResponse");

	crateRouter.generateOpenApi;
	crateRouter.generateEmber;

	listenHTTP(settings, router);
}

void generateOpenApi(T)(T crateRouter)
{
	auto api = crateRouter.toOpenApi;

	auto f = File("openApi.json", "w");

	f.write(api.serializeToJson.toPrettyString);
}

void generateEmber(T)(T crateRouter)
{
	crateRouter.toEmber!Book("./ember/");
}
