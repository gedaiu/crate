module crate.mongo;

import crate.base;
import crate.error;

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
		T[] list;
		auto cursor = collection.find!T();

		foreach(item; cursor) {
			list ~= item;
		}

		return list;
	}

	T addItem(T item)
	{
		auto id = BsonObjectID.generate();

		static if (is(item.id == BsonObjectID))
		{
			item._id = id;
		}
		else
		{
			item._id = id.to!string();
		}

		collection.insert(item);

		return item;
	}

	T getItem(string id)
	{
		if(collection.count(["_id": id]) == 0) {
			throw new CrateNotFoundException("There is no `" ~ T.stringof ~ "` with id `" ~ id ~ "`");
		}

		return collection.findOne!T(["_id": id]);
	}

	T editItem(string id, Json fields)
	{
		auto data = collection.findOne!Json(["_id": id]);

		foreach(string field, value; fields) {
			data[field] = value;
		}

		collection.findAndModify(["_id": id], data);

		return getItem(id);
	}

	void deleteItem(string id)
	{
		collection.remove(["_id": id]);
	}
}

version (unittest)
{
	import crate.request;
	import vibe.data.serialization;

	struct TestModel
	{
		@optional {
			string _id;
			string other = "";
		}
		string name = "";

		void action(string) {}
	}
}

unittest
{
	import vibe.db.mongo.mongo : connectMongoDB;

	auto client = connectMongoDB("127.0.0.1");
	auto collection = client.getCollection("test.model");

	auto router = new URLRouter();
	auto crate = new MongoCrate!TestModel(collection);

	auto crateRouter = new CrateRouter!TestModel(router, crate);

	Json data = Json.emptyObject;
	data["type"] = "testmodels";
	data["attributes"] = Json.emptyObject;
	data["attributes"]["name"] = "test name";

	request(router).post("/testmodels").send(data).expectHeader("Content-Type", "application/vnd.api+json")
		.expectHeaderContains("Location", "http://localhost/testmodels/").expectStatusCode(201)
		.end((Response response) => {
			auto id = response.bodyJson["data"]["id"].to!string;
			assert(response.headers["Location"] == "http://localhost/testmodels/" ~ id);
		});
}

unittest
{
	import vibe.db.mongo.mongo : connectMongoDB;

	auto client = connectMongoDB("127.0.0.1");
	auto collection = client.getCollection("test.model");
	collection.drop;
	collection.insert(TestModel("1"));
	collection.insert(TestModel("2"));

	auto router = new URLRouter();
	auto crate = new MongoCrate!TestModel(collection);
	auto crateRouter = new const CrateRouter!TestModel(router, crate);

	request(router).get("/testmodels").expectHeader("Content-Type", "application/vnd.api+json")
		.expectStatusCode(200)
		.end((Response response) => {
			assert(response.bodyJson["data"].length == 2);
			assert(response.bodyJson["data"][0]["id"].to!string == "1");
			assert(response.bodyJson["data"][1]["id"].to!string == "2");
		});
}

unittest
{
	import vibe.db.mongo.mongo : connectMongoDB;

	auto client = connectMongoDB("127.0.0.1");
	auto collection = client.getCollection("test.model");
	collection.drop;
	collection.insert(TestModel("1"));

	auto router = new URLRouter();
	auto crate = new MongoCrate!TestModel(collection);
	auto crateRouter = new const CrateRouter!TestModel(router, crate);

	request(router).get("/testmodels/1").expectHeader("Content-Type", "application/vnd.api+json")
		.expectStatusCode(200)
		.end((Response response) => {
			assert(response.bodyJson["data"]["id"].to!string == "1");
		});
}

unittest
{
	import vibe.db.mongo.mongo : connectMongoDB;

	auto client = connectMongoDB("127.0.0.1");
	auto collection = client.getCollection("test.model");
	collection.drop;
	collection.insert(TestModel("1", "", "testName"));

	auto router = new URLRouter();
	auto crate = new MongoCrate!TestModel(collection);
	auto crateRouter = new const CrateRouter!TestModel(router, crate);

	auto data = Json.emptyObject;
	data["data"] = Json.emptyObject;
	data["data"]["type"] = "testmodels";
	data["data"]["id"] = "1";
	data["data"]["attributes"] = Json.emptyObject;
	data["data"]["attributes"]["other"] = "other value";

	request(router).patch("/testmodels/1").send(data)
		.expectStatusCode(200)
		.expectHeader("Content-Type", "application/vnd.api+json")

		.end((Response response) => {
			assert(response.bodyJson["data"]["id"].to!string == "1");
			assert(response.bodyJson["data"]["type"].to!string == "testmodels");
			assert(response.bodyJson["data"]["attributes"]["name"].to!string == "testName");
			assert(response.bodyJson["data"]["attributes"]["other"].to!string == "other value");
		});
}

unittest
{
	import vibe.db.mongo.mongo : connectMongoDB;
	bool actionCalled;

	void action(TestModel) {
		actionCalled = true;
	}

	auto client = connectMongoDB("127.0.0.1");
	auto collection = client.getCollection("test.model");

	auto router = new URLRouter();
	auto crate = new MongoCrate!TestModel(collection);
	auto crateRouter = new CrateRouter!TestModel(router, crate);
	crateRouter.addAction!"action"(&action);

	request(router).get("/testmodels/1/action")
		.expectStatusCode(200)
		.expectHeader("Content-Type", "application/vnd.api+json")

		.end((Response response) => {
			assert(response.bodyString == "");
			assert(actionCalled);
		});
}

unittest
{
	import vibe.db.mongo.mongo : connectMongoDB;
	bool actionCalled;

	string action(TestModel) {
		actionCalled = true;

		return "test";
	}

	auto client = connectMongoDB("127.0.0.1");
	auto collection = client.getCollection("test.model");

	auto router = new URLRouter();
	auto crate = new MongoCrate!TestModel(collection);
	auto crateRouter = new CrateRouter!TestModel(router, crate);
	crateRouter.addAction!"action"(&action);

	request(router).get("/testmodels/1/action")
		.expectStatusCode(200)
		.expectHeader("Content-Type", "application/vnd.api+json")

		.end((Response response) => {
			assert(response.bodyString == "test");
			assert(actionCalled);
		});
}

unittest
{
	import vibe.db.mongo.mongo : connectMongoDB;
	bool actionCalled;

	struct Operation {
		int x;
		int y;
	}

	void action(TestModel, Operation operation) {
		assert(operation.x == 10);
		assert(operation.y == 20);

		actionCalled = true;
	}

	auto client = connectMongoDB("127.0.0.1");
	auto collection = client.getCollection("test.model");

	auto router = new URLRouter();
	auto crate = new MongoCrate!TestModel(collection);
	auto crateRouter = new CrateRouter!TestModel(router, crate);
	crateRouter.addAction!("action")(&action);

	auto data = Json.emptyObject;
	data.x = 10;
	data.y = 20;

	request(router).post("/testmodels/1/action")
		.send(data)
		.expectStatusCode(200)
		.expectHeader("Content-Type", "application/vnd.api+json")

		.end((Response response) => {
			assert(response.bodyString == "");
			assert(actionCalled);
		});
}


unittest
{
	import vibe.db.mongo.mongo : connectMongoDB;
	bool actionCalled;

	struct Operation {
		int x;
		int y;
	}

	string action(TestModel, Operation operation) {
		assert(operation.x == 10);
		assert(operation.y == 20);

		actionCalled = true;

		return "test";
	}

	auto client = connectMongoDB("127.0.0.1");
	auto collection = client.getCollection("test.model");

	auto router = new URLRouter();
	auto crate = new MongoCrate!TestModel(collection);
	auto crateRouter = new CrateRouter!TestModel(router, crate);
	crateRouter.addAction!("action")(&action);

	auto data = Json.emptyObject;
	data.x = 10;
	data.y = 20;

	request(router).post("/testmodels/1/action")
		.send(data)
		.expectStatusCode(200)
		.expectHeader("Content-Type", "application/vnd.api+json")

		.end((Response response) => {
			assert(response.bodyString == "test");
			assert(actionCalled);
		});
}

unittest
{
	import vibe.db.mongo.mongo : connectMongoDB;
	bool actionCalled;

	auto client = connectMongoDB("127.0.0.1");
	auto collection = client.getCollection("test.model");
	collection.drop;

	auto router = new URLRouter();
	auto crate = new MongoCrate!TestModel(collection);
	auto crateRouter = new CrateRouter!TestModel(router, crate);

	request(router).get("/testmodels/1")
		.expectStatusCode(404)
		.end((Response response) => {
			assert(response.bodyJson["errors"][0]["status"] == 404);
			assert(response.bodyJson["errors"][0]["title"] == "Crate not found");
			assert(response.bodyJson["errors"][0]["description"] == "There is no `TestModel` with id `1`");
		});
}

unittest
{
	import vibe.db.mongo.mongo : connectMongoDB;
	bool actionCalled;

	auto client = connectMongoDB("127.0.0.1");
	auto collection = client.getCollection("test.model");
	collection.drop;

	auto router = new URLRouter();
	auto crate = new MongoCrate!TestModel(collection);
	auto crateRouter = new CrateRouter!TestModel(router, crate);
	crateRouter.enableAction!"action";

	request(router).get("/testmodels/1/action")
		.expectStatusCode(200)
		.end((Response response) => {
			assert(response.bodyString == "");
		});
}
