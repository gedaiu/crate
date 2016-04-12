module crate.base;

import vibe.inet.url;
import vibe.http.router;
import vibe.data.json;
import vibe.data.bson;

import std.string, std.traits;

struct CrateConfig(T)
{
	string singular = T.stringof.toLower;
	string plural = T.stringof.toLower ~ "s";

	bool getList = true;
	bool getItem = true;
	bool addItem = true;
	bool deleteItem = true;
	bool editItem = true;
}

interface Crate(T)
{
	T[] getList();

	T addItem(T item);
	T getItem();
	void editItem(T item);
	void deleteItem(string id);
}

interface CrateSerializer(T)
{
	Json serialize(T item);
	T deserialize(Json data);
}

class CrateJsonApiSerializer(T) : CrateSerializer!T
{

	Json serialize(T item)
	{
		Json original = item.serializeToJson;
		Json value = Json.emptyObject;

		value["data"] = Json.emptyObject;

		static if(hasMember!(T, "id")) {
			value["data"]["id"] = original["id"];
		} else if(hasMember!(T, "_id")) {
			value["data"]["id"] = original["_id"];
		} else {
			static assert(T.stringof ~ " must contain `id` or `_id` field.");
		}

		value["data"]["type"] = T.stringof.toLower ~ "s";
		value["data"]["attributes"] = Json.emptyObject;

		foreach(string key, val; original) {
			if(key.to!string != "id") {
				value["data"]["attributes"][key] = val;
			}
		}

		return value;
	}

	T deserialize(Json data)
	{
		Json normalised = data["data"]["attributes"];

		static if(hasMember!(T, "id")) {
			normalised["id"] = data["data"]["id"];
		} else if(hasMember!(T, "_id")) {
			normalised["_id"] = data["data"]["id"];
		} else {
			static assert(T.stringof ~ " must contain either `id` or `_id` field.");
		}

		return deserializeJson!T(normalised);
	}
}

unittest
{
	struct TestModel
	{
		string id;

		string field1;
		int field2;
	}

	auto serializer = new CrateJsonApiSerializer!TestModel();

	//test the deserialize method
	auto serialized = `{
		"data": {
			"type": "testmodels",
			"id": "ID",
			"attributes": {
				"field1": "Ember Hamster",
				"field2": 5
			}
		}
	}`.parseJsonString;

	auto deserialized = serializer.deserialize(serialized);
	assert(deserialized.id == "ID");
	assert(deserialized.field1 == "Ember Hamster");
	assert(deserialized.field2 == 5);


	//test the serialize method
	auto value = serializer.serialize(deserialized);
	assert(value["data"]["type"] == "testmodels");
	assert(value["data"]["id"] == "ID");
	assert(value["data"]["attributes"]["field1"] == "Ember Hamster");
	assert(value["data"]["attributes"]["field2"] == 5);
}


unittest
{
	struct TestModel
	{
		BsonObjectID _id;

		string field1;
		int field2;
	}

	auto serializer = new CrateJsonApiSerializer!TestModel();

	//test the deserialize method
	auto serialized = `{
		"data": {
			"type": "testmodels",
			"id": "570d5afa999f19d459000000",
			"attributes": {
				"field1": "Ember Hamster",
				"field2": 5
			}
		}
	}`.parseJsonString;

	auto deserialized = serializer.deserialize(serialized);
	assert(deserialized._id.to!string == "570d5afa999f19d459000000");

	//test the serialize method
	auto value = serializer.serialize(deserialized);
	assert(value["data"]["id"] == "570d5afa999f19d459000000");
}

class CrateRouter(T)
{
	CrateConfig!T config;
	CrateSerializer!T serializer;

	private
	{
		Crate!T crate;
	}

	this(URLRouter router, Crate!T crate)
	{
		this.serializer = new CrateJsonApiSerializer!T();
		this.crate = crate;

		router.get("/" ~ config.plural, &getList);
		router.post("/" ~ config.plural, &postItem);

		router.get("/" ~ config.plural ~ "/:id", &getItem);
		router.post("/" ~ config.plural ~ "/:id", &updateItem);
		router.delete_("/" ~ config.plural ~ "/:id", &deleteItem);
	}

	void getItem(HTTPServerRequest request, HTTPServerResponse response)
	{

	}

	void updateItem(HTTPServerRequest request, HTTPServerResponse response)
	{

	}

	void deleteItem(HTTPServerRequest request, HTTPServerResponse response)
	{

	}

	void getList(HTTPServerRequest request, HTTPServerResponse response)
	{
		response.headers["Content-Type"] = "application/vnd.api+json";
		response.writeJsonBody(crate.getList);
	}

	void postItem(HTTPServerRequest request, HTTPServerResponse response)
	{
		response.headers["Location"] = "http://localhost/testModels/";

		auto item = crate.addItem(request.json.attributes.deserializeJson!T);

		response.writeJsonBody(serializer.serialize(item), 201, "application/vnd.api+json");
	}
}
