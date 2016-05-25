module crate.serializer.restapi;

import crate.base, crate.ctfe, crate.generator.openapi;
import crate.error;

import vibe.data.json;
import vibe.data.bson;

import swaggerize.definitions;

import std.meta, std.string, std.exception;
import std.algorithm.searching, std.algorithm.iteration;

import std.traits, std.stdio, std.meta, std.conv;

class CrateRestApiSerializer(T) : CrateSerializer!T
{

	private immutable {
		string singular;
		string plural;
	}

	this() inout {
		enum singular = Singular!T[0..1].toLower ~ Singular!T[1..$];
		enum plural = Plural!T[0..1].toLower ~ Plural!T[1..$];

		this(singular, plural);
	}

	this(string singular, string plural) inout {
		this.singular = singular;
		this.plural = plural;
	}

	Json denormalise(Json[] data) inout {
		Json result = Json.emptyObject;

		result[plural] = Json.emptyArray;

		foreach(item; data) {
			result[plural] ~= item;
		}

		return result;
	}

	Json denormalise(Json data) inout {
		Json result = Json.emptyObject;

		result[singular] = data;

		return result;
	}

	Json normalise(Json data) inout
	{
		enforce!CrateValidationException(singular in data,
				"object type expected to be `" ~ singular ~ "`");
		return data[singular];
	}
}

@("Serialize/deserialize a simple struct")
unittest
{
	struct TestModel
	{
		string id;

		string field1;
		int field2;
	}

	auto serializer = new CrateRestApiSerializer!TestModel();

	//test the deserialize method
	auto serialized = `{
		"testModel": {
				"id": "ID",
				"field1": "Ember Hamster",
				"field2": 5
		}
	}`.parseJsonString;

	auto deserialized = serializer.normalise(serialized);
	assert(deserialized["id"] == "ID");
	assert(deserialized["field1"] == "Ember Hamster");
	assert(deserialized["field2"] == 5);

	//test the denormalise method
	auto value = serializer.denormalise(deserialized);
	assert(value["testModel"]["id"] == "ID");
	assert(value["testModel"]["field1"] == "Ember Hamster");
	assert(value["testModel"]["field2"] == 5);
}

@("Serialize an array of structs")
unittest
{
	struct TestModel
	{
		string id;

		string field1;
		int field2;
	}

	auto serializer = new CrateRestApiSerializer!TestModel();

	Json[] data = [
		TestModel("ID1", "Ember Hamster", 5).serializeToJson,
		TestModel("ID2", "Ember Hamster2", 6).serializeToJson
	];

	//test the serialize method
	auto value = serializer.denormalise(data);

	assert(value["testModels"][0]["id"] == "ID1");
	assert(value["testModels"][0]["field1"] == "Ember Hamster");
	assert(value["testModels"][0]["field2"] == 5);

	assert(value["testModels"][1]["id"] == "ID2");
	assert(value["testModels"][1]["field1"] == "Ember Hamster2");
	assert(value["testModels"][1]["field2"] == 6);
}

@("Check denormalised type")
unittest
{
	@("singular: SingularModel", "plural: PluralModel")
	struct TestModel
	{
		@optional
		{
			string _id;
		}
	}

	auto serializer = new CrateRestApiSerializer!TestModel;
	auto valueSingular = const serializer.denormalise(TestModel().serializeToJson);
	auto valuePlural = const serializer.denormalise([ TestModel().serializeToJson ]);

	assert("singularModel" in valueSingular);
	assert("pluralModel" in valuePlural);

	assert("_id" in serializer.normalise(valueSingular));
}
