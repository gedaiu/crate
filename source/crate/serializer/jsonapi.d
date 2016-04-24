module crate.serializer.jsonapi;

import crate.base;

import vibe.data.json;
import vibe.data.bson;

import swaggerize.definitions;

import std.traits, std.stdio, std.meta;

class CrateJsonApiSerializer(T) : CrateSerializer!T
{
	CrateConfig!T config;

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

		value["type"] = config.plural;
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

		foreach (item; items)
		{
			value["data"] ~= sertializeToData(item);
		}

		return value;
	}

	T deserialize(Json data)
	{
		assert(data["data"]["type"].to!string == config.plural);

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

	string mime() {
		return "application/vnd.api+json";
	}

	ModelDefinition definition() {
		ModelDefinition model;

		string typeString(T)() {
			return T.stringof;
		}

		auto fields = [ staticMap!(typeString, Fields!T) ];
		alias names = FieldNameTuple!T;
		T instance;

		foreach(name; names) {
			mixin("alias symbol = instance." ~ name ~ ";");

			if(!hasUDA!(symbol, ignore)) {
				model.fields[name] = ModelType(fields[0]);
			}

			fields = fields[1..$];
		}

		return model;
	}
}

unittest {
	struct TestModel
	{
		string id;

		string field1;
		int field2;

		@ignore
		int field3;
	}

	auto serializer = new CrateJsonApiSerializer!TestModel();

	auto definition = serializer.definition;
	definition.idField = "id";
	assert(definition.fields["id"].type == "string");
	assert(definition.fields["id"].isComposite == false);
	assert(definition.fields["field1"].type == "string");
	assert(definition.fields["field1"].isComposite == false);
	assert(definition.fields["field2"].type == "int");
	assert(definition.fields["field2"].isComposite == false);

	assert("field3" !in definition.fields);
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
