module crate.collection.mongo;

import crate.base;
import crate.error;
import crate.ctfe;

import vibe.inet.url;
import vibe.http.router;
import vibe.data.json;
import vibe.db.mongo.collection;
import vibe.db.mongo.mongo;

import std.conv, std.stdio, std.array, std.range.interfaces;
import std.algorithm, std.typecons, std.exception;

class MongoCrateRange : ICrateSelector
{
	private {
		MongoCollection collection;
		Json query;
		size_t resultCount;
	}

	this(MongoCollection collection) {
		this.collection = collection;
		this.query = Json.emptyObject;
	}

	override {
		ICrateSelector where(string field, string value) {
			query[field] = value;

			return this;
		}

		ICrateSelector whereArrayContains(string field, string value) {
			query[field] = Json.emptyObject;
			query[field]["$elemMatch"] = Json.emptyObject;
			query[field]["$elemMatch"]["$eq"] = value;

			return this;
		}

		ICrateSelector whereArrayFieldContains(string arrayField, string field, string value) {
			query[arrayField] = Json.emptyObject;
			query[arrayField]["$elemMatch"] = Json.emptyObject;
			query[arrayField]["$elemMatch"][field] = value;

			return this;
		}

		ICrateSelector limit(ulong nr) {
			resultCount = nr;

			return this;
		}

		InputRange!Json exec() {
			class MongoRange : InputRange!Json {
				alias Cursor = MongoCursor!(Json, Json, typeof(null));
				Cursor cursor;

				this(Cursor cursor) {
					this.cursor = cursor;
				}

				@property {
					Json front() {
						return cursor.front;
					}

					Json moveFront() {
						auto data = cursor.front;
						cursor.popFront;

						return data;
					}

					bool empty() {
						return cursor.empty;
					}
				}

				void popFront() {
					cursor.popFront;
				}

				int opApply(scope int delegate(Json) d) {
					int d2(ref Json data) {
						return d(data);
					}

					return cursor.opApply(&d2);
				}

				int opApply(scope int delegate(size_t, Json) d) {
					int d2(ref ulong idx, ref Json data) {
						return d(idx, data);
					}

					return cursor.opApply(&d2);
				}
			}

			return new MongoRange(collection.find!Json(query).limit(resultCount));
		}
	}
}

class MongoCrate(T): Crate!T
{
	private {
		MongoCollection collection;
		CrateConfig!T _config;
	}

	this(MongoCollection collection, CrateConfig!T config = CrateConfig!T())
	{
		this.collection = collection;
		this._config = config;
	}

	this(MongoClient client, string collection, CrateConfig!T config = CrateConfig!T()) {
		this.collection = client.getCollection(collection);
		this._config = config;
	}

	CrateConfig!T config() {
		return _config;
	}

	ICrateSelector get() {
    return new MongoCrateRange(collection);
  }

	ICrateSelector getList(string[string])
	{
		return get();
	}

	Json addItem(Json item)
	{
		item["_id"] = BsonObjectID.generate().to!string;

		collection.insert(toBson!T(item));

		return item;
	}

	Json getItem(string id)
	{
		if (collection.count(["_id" : toId(id, collection.name)]) == 0)
		{
			throw new CrateNotFoundException("There is no item with id `" ~ id ~ "` inside `" ~ collection.name ~ "`");
		}

		return collection.findOne!Json(["_id" : toId(id, collection.name)]);
	}

	Json editItem(string id, Json fields)
	{
		if (collection.count(["_id" : toId(id, collection.name)]) == 0)
		{
			throw new CrateNotFoundException("There is no item with id `" ~ id ~ "` inside `" ~ collection.name ~ "`");
		}

		auto data = toBson!T(fields);

		collection.update(["_id" : toId(id, collection.name)], data);

		return getItem(id);
	}

	void updateItem(Json item)
	{
		auto updateItem = toBson!T(item);

		collection.update(["_id" : toId(item["_id"].to!string, collection.name)], updateItem);
	}

	void deleteItem(string id)
	{
		if (collection.count(["_id" : toId(id, collection.name)]) == 0)
		{
			throw new CrateNotFoundException("There is no item with id `" ~ id ~ "` inside `" ~ collection.name ~ "`");
		}

		collection.remove(["_id" : toId(id, collection.name)]);
	}
}

version (unittest)
{
	import crate.http.router;
	import fluentasserts.vibe.request;
	import vibe.data.serialization;

	bool isTestActionCalled;

	struct EmbededModel {
		string field;
		TestModel relation;
	}

	struct RelationModel
	{
		BsonObjectID _id;
		string name = "";

		EmbededModel embeded;
		TestModel relation;
		TestModel[] relations;
	}

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

auto toId(string id, string type = "") {
	enforce!CrateNotFoundException(id.length == 24, "There is no item with id `" ~ id ~ "` inside `" ~ type ~ "`");

	try {
		return BsonObjectID.fromString(id);
	} catch (ConvException e) {
		throw new CrateNotFoundException("There is no item with id `" ~ id ~ "` inside `" ~ type ~ "`");
	}
}

Bson toBson(FieldDefinition definition, Json model, string parent = "unknown model") {
	if(definition.isId) {
		return Bson(model.to!string.toId(parent));
	}

	if(definition.isArray) {
		auto tmpField = definition;
		tmpField.isArray = false;

		auto r = (cast(Json[])model).map!(item => toBson(tmpField.fields[0], item));
		return Bson(r.array);
	}

	if(definition.isRelation) {
		foreach(f; definition.fields) {
			if(f.isId) {
				return Bson(model[f.name].to!string.toId(definition.type));
			}
		}

		enforce!CrateValidationException(false, "No `id` field for `" ~ definition.name ~ "` inside `" ~ definition.type ~ "`");
	}

	if(!definition.isBasicType && model.type == Json.Type.object) {
		Bson data = Bson.emptyObject;

		definition.fields
			.map!(field => tuple!("name", "value")(field.name, toBson(field, model[field.name], definition.type)))
			.array
			.each!(item => data[item.name] = item.value);

		return data;
	}

	return Bson.fromJson(model);
}

Bson toBson(T)(Json model) {
	return toBson(getFields!T, model);
}

version(unittest) {
	import fluent.asserts;
}

@("Check model to bson conversion")
unittest {
	RelationModel model;
	model.embeded.field = "field";
	model.embeded.relation._id = BsonObjectID.generate;
	model._id = BsonObjectID.generate;
	model.relation = TestModel(BsonObjectID.generate, "other1");
	model.relations = [ TestModel(BsonObjectID.generate, "other1") ];
	model.name = "test";

	auto result = model.serializeToJson.toBson!RelationModel;

	assert(result["_id"].toJson.to!string == model._id.to!string);
	assert(result["name"].get!string == "test");
	assert(result["embeded"]["field"].get!string == "field");
	assert(result["embeded"]["relation"].toJson.to!string == model.embeded.relation._id.to!string);
	assert(result["relation"].toJson.to!string == model.relation._id.to!string);
	assert(result["relations"].length == 1);
	assert(result["relations"][0].toJson.to!string == model.relations[0]._id.to!string);
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

	try {
		collection.drop;
	} catch(Exception) {}
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

	try {
		collection.drop;
	} catch(Exception) {}

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

@("It should return existing resources")
unittest
{
	import vibe.db.mongo.mongo : connectMongoDB;
	import crate.policy.jsonapi : CrateJsonApiPolicy;

	auto client = connectMongoDB("127.0.0.1");
	auto collection = client.getCollection("test.model");

	try {
		collection.drop;
	} catch(Exception) {}

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

@("It should get a 404 error on missing resources")
unittest
{
	import vibe.db.mongo.mongo : connectMongoDB;
	import crate.policy.jsonapi : CrateJsonApiPolicy;

	bool actionCalled;

	auto client = connectMongoDB("127.0.0.1");
	auto collection = client.getCollection("test.model");

	try {
		collection.drop;
	} catch (Exception) {}

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
	collection.drop;
	collection.insert(TestModel(BsonObjectID.fromString("573cbc2fc3b7025427000000")));

	auto router = new URLRouter();
	auto crate = new MongoCrate!TestModel(collection);
	router.crateSetup!CrateJsonApiPolicy.add(crate).enableAction!(MongoCrate!TestModel, "action");

	request(router).get("/testmodels/573cbc2fc3b7025427000000/action").expectStatusCode(200).end((Response response) => {
		response.bodyString.should.equal("");
		isTestActionCalled.should.equal(true);
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

	router.crateSetup!CrateJsonApiPolicy.add(crate).enableAction!(MongoCrate!TestModel, "actionResponse");

	request(router).get("/testmodels/573cbc2fc3b7025427000000/actionResponse").expectStatusCode(200)
		.end((Response response) => {
			assert(response.bodyString == "ok.");
			assert(isTestActionCalled);
		});
}

@("it should add the access control headers")
unittest
{
	import vibe.db.mongo.mongo : connectMongoDB;
	import crate.policy.jsonapi : CrateJsonApiPolicy;

	isTestActionCalled = false;

	auto client = connectMongoDB("127.0.0.1");
	auto collection = client.getCollection("test.model");

	try {
		collection.drop;
	} catch(Exception) { }

	collection.insert(TestModel(BsonObjectID.fromString("573cbc2fc3b7025427000000")));

	auto router = new URLRouter();
	auto crate = new MongoCrate!TestModel(collection);

	router.crateSetup.add(crate);

	request(router).get("/testmodels")
		.expectHeader("Access-Control-Allow-Origin", "*")
		.end();
}
