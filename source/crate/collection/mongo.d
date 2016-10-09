module crate.collection.mongo;

import crate.base;
import crate.error;

import vibe.inet.url;
import vibe.http.router;
import vibe.data.json;
import vibe.db.mongo.collection;

import std.conv, std.stdio;

class MongoCrate(T): Crate!T
{
	private {
		MongoCollection collection;
		CrateConfig _config;
	}

	this(MongoCollection collection, CrateConfig config = CrateConfig())
	{
		this.collection = collection;
		this._config = config;
	}

	CrateConfig config() {
		return _config;
	}

	Json[] getList()
	{
		Json[] list;
		auto cursor = collection.find!Json();

		foreach (item; cursor)
		{
			list ~= item;
		}

		return list;
	}

	Json addItem(Json item)
	{
		item["_id"] = BsonObjectID.generate().to!string;

		collection.insert(toBson(item));

		return item;
	}

	Json getItem(string id)
	{
		if (collection.count(["_id" : toId(id)]) == 0)
		{
			throw new CrateNotFoundException("There is no item with id `" ~ id ~ "` inside `" ~ collection.name ~ "`");
		}

		return collection.findOne!Json(["_id" : toId(id)]);
	}

	Json editItem(string id, Json fields)
	{
		if (collection.count(["_id" : toId(id)]) == 0)
		{
			throw new CrateNotFoundException("There is no item with id `" ~ id ~ "` inside `" ~ collection.name ~ "`");
		}

		auto data = toBson(fields);

		collection.update(["_id" : toId(id)], data);

		return getItem(id);
	}

	void updateItem(Json item)
	{
		auto updateItem = toBson(item);

		collection.update(["_id" : toId(item["_id"].to!string)], updateItem);
	}

	private auto toId(string id) {
		try {
			return BsonObjectID.fromString(id);
		} catch (ConvException e) {
			throw new CrateNotFoundException("There is no item with id `" ~ id ~ "` inside `" ~ collection.name ~ "`");
		}
	}

	private Bson toBson(Json data) {
		if(data.type == Json.Type.int_ || data.type == Json.Type.bigInt) {
			return Bson(data.to!long.to!double);
		} else if(data.type == Json.Type.object) {
			Bson object = Bson.emptyObject;

			foreach(string key, value; data) {
				if(key == "_id") {
					object[key] = BsonObjectID.fromString(value.to!string);
				} else {
					object[key] = toBson(value);
				}
			}

			return object;
		} else if(data.type == Json.Type.array) {
			Bson[] list = [];

			foreach(value; data) {
				list ~= toBson(value);
			}

			return Bson(list);
		} else {
			return Bson.fromJson(data);
		}
	}

	void deleteItem(string id)
	{
		if (collection.count(["_id" : toId(id)]) == 0)
		{
			throw new CrateNotFoundException("There is no item with id `" ~ id ~ "` inside `" ~ collection.name ~ "`");
		}

		collection.remove(["_id" : toId(id)]);
	}
}

version (unittest)
{
	import crate.http.router;
	import crate.request;
	import vibe.data.serialization;

	bool isTestActionCalled;

	struct TestModel
	{
		@optional
		{
			BsonObjectID _id;
			string other = "";
		}

		string name = "";

		void action()
		{
			isTestActionCalled = true;
		}

		string actionResponse()
		{
			isTestActionCalled = true;

			return "ok.";
		}

		void actionChange()
		{
			name = "changed";
		}
	}
}

unittest
{
	import vibe.db.mongo.mongo : connectMongoDB;
	import crate.policy.jsonapi : CrateJsonApiPolicy;

	auto client = connectMongoDB("127.0.0.1");
	auto collection = client.getCollection("test.model");

	auto router = new URLRouter();
	auto crate = new MongoCrate!TestModel(collection);

	router.crateSetup!CrateJsonApiPolicy.add(crate);

	Json data = Json.emptyObject;
	data["data"] = Json.emptyObject;
	data["data"]["type"] = "testmodels";
	data["data"]["attributes"] = Json.emptyObject;
	data["data"]["attributes"]["name"] = "test name";

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
	import crate.policy.jsonapi : CrateJsonApiPolicy;

	auto client = connectMongoDB("127.0.0.1");
	auto collection = client.getCollection("test.model");
	collection.drop;
	collection.insert(TestModel(BsonObjectID.fromString("573cbc2fc3b7025427000000")));
	collection.insert(TestModel(BsonObjectID.fromString("573cbc2fc3b7025427000001")));

	auto router = new URLRouter();
	auto crate = new MongoCrate!TestModel(collection);

	router.crateSetup!CrateJsonApiPolicy.add(crate);

	request(router).get("/testmodels").expectHeader("Content-Type",
			"application/vnd.api+json").expectStatusCode(200).end((Response response) => {
		assert(response.bodyJson["data"].length == 2);
		assert(response.bodyJson["data"][0]["id"].to!string == "573cbc2fc3b7025427000000");
		assert(response.bodyJson["data"][1]["id"].to!string == "573cbc2fc3b7025427000001");
	});
}

unittest
{
	import vibe.db.mongo.mongo : connectMongoDB;
	import crate.policy.jsonapi : CrateJsonApiPolicy;

	auto client = connectMongoDB("127.0.0.1");
	auto collection = client.getCollection("test.model");
	collection.drop;
	collection.insert(TestModel(BsonObjectID.fromString("573cbc2fc3b7025427000000")));

	auto router = new URLRouter();
	auto crate = new MongoCrate!TestModel(collection);

	router.crateSetup!CrateJsonApiPolicy.add(crate);

	request(router)
		.get("/testmodels/573cbc2fc3b7025427000000")
		.expectHeader("Content-Type", "application/vnd.api+json")
		.expectStatusCode(200)
		.end((Response response) => {
			assert(response.bodyJson["data"]["id"].to!string == "573cbc2fc3b7025427000000");
		});
}

unittest
{
	import vibe.db.mongo.mongo : connectMongoDB;
	import crate.policy.jsonapi : CrateJsonApiPolicy;

	auto client = connectMongoDB("127.0.0.1");
	auto collection = client.getCollection("test.model");
	collection.drop;
	collection.insert(TestModel(BsonObjectID.fromString("573cbc2fc3b7025427000000"), "", "testName"));

	auto router = new URLRouter();
	auto crate = new MongoCrate!TestModel(collection);

	router.crateSetup!CrateJsonApiPolicy.add(crate);

	auto data = Json.emptyObject;
	data["data"] = Json.emptyObject;
	data["data"]["type"] = "testmodels";
	data["data"]["id"] = "573cbc2fc3b7025427000000";
	data["data"]["attributes"] = Json.emptyObject;
	data["data"]["attributes"]["other"] = "other value";

	request(router).patch("/testmodels/573cbc2fc3b7025427000000").send(data).expectStatusCode(200)
		.expectHeader("Content-Type", "application/vnd.api+json").end((Response response) => {
			assert(response.bodyJson["data"]["id"].to!string == "573cbc2fc3b7025427000000");
			assert(response.bodyJson["data"]["type"].to!string == "testmodels");
			assert(response.bodyJson["data"]["attributes"]["name"].to!string == "testName");
			assert(response.bodyJson["data"]["attributes"]["other"].to!string == "other value");
		});
}

unittest
{
	import vibe.db.mongo.mongo : connectMongoDB;
	import crate.policy.jsonapi : CrateJsonApiPolicy;

	bool actionCalled;

	auto client = connectMongoDB("127.0.0.1");
	auto collection = client.getCollection("test.model");
	collection.drop;

	auto router = new URLRouter();
	auto crate = new MongoCrate!TestModel(collection);

	router.crateSetup!CrateJsonApiPolicy.add(crate);

	request(router).get("/testmodels/1").expectStatusCode(404).end((Response response) => {
		assert(response.bodyJson["errors"][0]["status"] == 404);
		assert(response.bodyJson["errors"][0]["title"] == "Crate not found");
		assert(response.bodyJson["errors"][0]["description"] == "There is no item with id `1` inside `model`");
	});
}

unittest
{
	import vibe.db.mongo.mongo : connectMongoDB;
	import crate.policy.jsonapi : CrateJsonApiPolicy;

	isTestActionCalled = false;

	auto client = connectMongoDB("127.0.0.1");
	auto collection = client.getCollection("test.model");
	collection.insert(TestModel(BsonObjectID.fromString("573cbc2fc3b7025427000000")));

	auto router = new URLRouter();
	auto crate = new MongoCrate!TestModel(collection);
	router.crateSetup!CrateJsonApiPolicy.add(crate).enableAction!(TestModel, "action");

	request(router).get("/testmodels/573cbc2fc3b7025427000000/action").expectStatusCode(200).end((Response response) => {
		assert(response.bodyString == "");
		assert(isTestActionCalled);
	});
}

unittest
{
	import vibe.db.mongo.mongo : connectMongoDB;
	import crate.policy.jsonapi : CrateJsonApiPolicy;

	isTestActionCalled = false;

	auto client = connectMongoDB("127.0.0.1");
	auto collection = client.getCollection("test.model");
	collection.drop;
	collection.insert(TestModel(BsonObjectID.fromString("573cbc2fc3b7025427000000")));

	auto router = new URLRouter();
	auto crate = new MongoCrate!TestModel(collection);

	router.crateSetup!CrateJsonApiPolicy.add(crate).enableAction!(TestModel, "actionResponse");

	request(router).get("/testmodels/573cbc2fc3b7025427000000/actionResponse").expectStatusCode(200)
		.end((Response response) => {
			assert(response.bodyString == "ok.");
			assert(isTestActionCalled);
		});
}

unittest
{
	import vibe.db.mongo.mongo : connectMongoDB;
	import crate.policy.jsonapi : CrateJsonApiPolicy;

	isTestActionCalled = false;

	auto client = connectMongoDB("127.0.0.1");
	auto collection = client.getCollection("test.model");
	collection.drop;
	collection.insert(TestModel(BsonObjectID.fromString("573cbc2fc3b7025427000000")));

	auto router = new URLRouter();
	auto crate = new MongoCrate!TestModel(collection);

	router.crateSetup.add(crate);

	request(router).get("/testmodels")
		.expectHeader("Access-Control-Allow-Origin", "*").end((Response response) => { });
}
