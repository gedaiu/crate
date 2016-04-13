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
	T getItem(string id);
	T editItem(string id, Json fields);
	void deleteItem(string id);
}

interface CrateSerializer(T)
{
	Json serialize(T item);
	Json serialize(T[] items);

	T deserialize(Json data);
}

class CrateJsonApiSerializer(T) : CrateSerializer!T
{
	Json sertializeToData(T item)
	{
		Json original = item.serializeToJson;
		auto value = Json.emptyObject;

		static if (hasMember!(T, "id"))
		{
			value["id"] = original["id"];
		}
		else if (hasMember!(T, "_id"))
		{
			value["id"] = original["_id"];
		}
		else
		{
			static assert(T.stringof ~ " must contain `id` or `_id` field.");
		}

		value["type"] = T.stringof.toLower ~ "s";
		value["attributes"] = Json.emptyObject;

		foreach (string key, val; original)
		{
			if (key.to!string != "id")
			{
				value["attributes"][key] = val;
			}
		}

		return value;
	}

	Json serialize(T item)
	{
		Json value = Json.emptyObject;

		value["data"] = sertializeToData(item);

		return value;
	}

	Json serialize(T[] items)
	{
		Json value = Json.emptyObject;
		value["data"] = Json.emptyArray;

		foreach(item; items) {
			value["data"] ~= sertializeToData(item);
		}

		return value;
	}

	T deserialize(Json data)
	{
		assert(data["data"]["type"].to!string == T.stringof.toLower ~ "s");

		Json normalised = data["data"]["attributes"];

		static if (hasMember!(T, "id"))
		{
			normalised["id"] = data["data"]["id"];
		}
		else if (hasMember!(T, "_id"))
		{
			normalised["_id"] = data["data"]["id"];
		}
		else
		{
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
	bool raised;

	try
	{
		serializer.deserialize(`{
			"data": {
				"type": "unknown",
				"id": "570d5afa999f19d459000000",
				"attributes": {
					"field1": "Ember Hamster",
					"field2": 5
				}
			}
		}`.parseJsonString);
	}
	catch (Throwable)
	{
		raised = true;
	}

	assert(raised);
}

class CrateRouter(T)
{
	CrateConfig!T config;
	CrateSerializer!T serializer;
	enum string itemName = T.stringof.toLower ~ "s";

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
		router.patch("/" ~ config.plural ~ "/:id", &updateItem);
		router.delete_("/" ~ config.plural ~ "/:id", &deleteItem);
	}

	void getItem(HTTPServerRequest request, HTTPServerResponse response)
	{
		auto data = crate.getItem(request.params["id"]);
		response.writeJsonBody(serializer.serialize(data), 200, "application/vnd.api+json");
	}

	void updateItem(HTTPServerRequest request, HTTPServerResponse response)
	{
		auto data = crate.editItem(request.params["id"], request.json.attributes);
		response.writeJsonBody(serializer.serialize(data), 200, "application/vnd.api+json");
	}

	void deleteItem(HTTPServerRequest request, HTTPServerResponse response)
	{
		crate.deleteItem(request.params["id"]);
		response.writeBody("", 204, "application/vnd.api+json");
	}

	void getList(HTTPServerRequest request, HTTPServerResponse response)
	{
		auto data = crate.getList;
		response.writeJsonBody(serializer.serialize(data), 200, "application/vnd.api+json");
	}

	void postItem(HTTPServerRequest request, HTTPServerResponse response)
	{
		auto item = crate.addItem(request.json.attributes.deserializeJson!T);
		auto data = serializer.serialize(item);

		response.headers["Location"] = (request.fullURL ~ Path(data["data"]["id"].to!string))
			.to!string;
		response.writeJsonBody(data, 201, "application/vnd.api+json");
	}
}
