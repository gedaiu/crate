module crate.mongo;

import crate.base;

import vibe.inet.url;
import vibe.http.router;
import vibe.data.json;
import vibe.db.mongo.collection;

class MongoCrate(T) : Crate!T
{
	private MongoCollection collection;

	this(MongoCollection collection)
	{
		this.collection = collection;
	}

	T[] getList()
	{
		throw new Exception("Not implemented");
	}

	T addItem(T item)
	{
		auto id = BsonObjectID.generate();

		static if (is(item.id == BsonObjectID))
		{
			item.id = id;
		}
		else
		{
			item.id = id.to!string();
		}

		collection.insert(item);

		return item;
	}

	T getItem()
	{
		throw new Exception("Not implemented");
	}

	void editItem(T item)
	{
		throw new Exception("Not implemented");
	}

	void deleteItem(string id)
	{
		throw new Exception("Not implemented");
	}
}

version (unittest)
{
	import crate.request;

	struct TestModel
	{
		@optional string id;
		string name = "";
	}
}

unittest
{
	import vibe.db.mongo.mongo : connectMongoDB;

	auto client = connectMongoDB("127.0.0.1");
	auto collection = client.getCollection("test.model");

	auto router = new URLRouter();
	auto crate = new MongoCrate!TestModel(collection);

	auto crateRouter = new const CrateRouter!TestModel(router, crate);

	Json data = Json.emptyObject;
	data["type"] = "testmodels";
	data["attributes"] = Json.emptyObject;
	data["attributes"]["name"] = "test name";

	request(router).post("/testmodels").send(data).expectHeader("Content-Type", "application/vnd.api+json")
		.expectHeaderContains("Location", "http://localhost/testModels/").expectStatusCode(201)
		.end((Response response) => { std.stdio.writeln(response.bodyString); });
}
