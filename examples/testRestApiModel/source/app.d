import vibe.d;

import crate.mongo;
import crate.router;
import crate.openapi;
import crate.serializer.restapi;
import std.stdio;

struct Comment {
	BsonObjectID userId;
	string message;
}

struct Book
{
	@optional {
		BsonObjectID _id;
	}

	string name;
	string author;
	string category;

	@optional
	int something;

	double price;
	bool inStock;

	//@optional
	//Comment[] comments;

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
	writeln("a1");
	auto settings = new HTTPServerSettings;
	settings.port = 9090;
	settings.options = HTTPServerOption.parseQueryString
		| HTTPServerOption.parseFormBody | HTTPServerOption.parseJsonBody;

	writeln("a2");
	auto client = connectMongoDB("127.0.0.1");

	writeln("a3");
	auto router = new URLRouter;

	writeln("a4");
	auto collection = client.getCollection("test.model");
	writeln("a5");
	auto crate = new MongoCrate!Book(collection);
	writeln("a6");
	//auto serializer = new CrateRestApiSerializer!TestModel;
	writeln("a7");

	auto crateRouter = new CrateRouter!Book(router, crate);
	crateRouter.enableAction!"action";
	crateRouter.enableAction!"actionResponse";

	//crateRouter.generateOpenApi;

	listenHTTP(settings, router);
}

void generateOpenApi(T)(T crateRouter)
{
	auto api = crateRouter.toOpenApi;

	auto f = File("openApi.json", "w");

	f.write(api.serializeToJson.toPrettyString);
}
