module crate.serializer.restapi;

import crate.base, crate.ctfe, crate.generator.openapi;
import crate.error;

import vibe.data.json;
import vibe.data.bson;

import swaggerize.definitions;

import std.meta, std.string, std.exception;
import std.algorithm.searching, std.algorithm.iteration;

import std.traits, std.stdio, std.meta, std.conv;

class CrateRestApiSerializer : CrateSerializer
{

	Json denormalise(Json[] data, ref const FieldDefinition definition) inout {
		Json result = Json.emptyObject;

		result[plural(definition)] = Json.emptyArray;

		foreach(item; data) {
			result[plural(definition)] ~= item;
		}

		return result;
	}

	Json denormalise(Json data, ref const FieldDefinition definition) inout {
		Json result = Json.emptyObject;

		result[singular(definition)] = data;

		return result;
	}

	Json normalise(Json data, ref const FieldDefinition definition) inout
	{
		enforce!CrateValidationException(singular(definition) in data,
				"object type expected to be `" ~ singular(definition) ~ "`");
		return data[singular(definition)];
	}

	private inout pure {
		string singular(const FieldDefinition definition) {
			return definition.singular[0..1].toLower ~ definition.singular[1..$];
		}

		string plural(const FieldDefinition definition) {
			return definition.plural[0..1].toLower ~ definition.plural[1..$];
		}
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

	auto fields = getFields!TestModel;
	auto serializer = new const CrateRestApiSerializer;

	//test the deserialize method
	auto serialized = `{
		"testModel": {
				"id": "ID",
				"field1": "Ember Hamster",
				"field2": 5
		}
	}`.parseJsonString;

	auto deserialized = serializer.normalise(serialized, fields);
	assert(deserialized["id"] == "ID");
	assert(deserialized["field1"] == "Ember Hamster");
	assert(deserialized["field2"] == 5);

	//test the denormalise method
	auto value = serializer.denormalise(deserialized, fields);
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

	auto fields = getFields!TestModel;
	auto serializer = new const CrateRestApiSerializer;

	Json[] data = [
		TestModel("ID1", "Ember Hamster", 5).serializeToJson,
		TestModel("ID2", "Ember Hamster2", 6).serializeToJson
	];

	//test the serialize method
	auto value = serializer.denormalise(data, fields);

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

	auto fields = getFields!TestModel;
	auto serializer = new const CrateRestApiSerializer;
	auto valueSingular = const serializer.denormalise(TestModel().serializeToJson, fields);
	auto valuePlural = const serializer.denormalise([ TestModel().serializeToJson ], fields);

	assert("singularModel" in valueSingular);
	assert("pluralModel" in valuePlural);

	assert("_id" in serializer.normalise(valueSingular, fields));
}
