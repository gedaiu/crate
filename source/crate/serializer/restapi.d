module crate.serializer.restapi;

import crate.base, crate.ctfe, crate.generator.openapi;
import crate.error;

import vibe.data.json;
import vibe.data.bson;

import swaggerize.definitions;

import std.meta, std.string, std.exception, std.array;
import std.algorithm.searching, std.algorithm.iteration;

import std.traits, std.stdio, std.meta, std.conv;

class CrateRestApiSerializer : CrateSerializer
{

	Json denormalise(Json[] data, ref const FieldDefinition definition) inout {
		Json result = Json.emptyObject;

		result[plural(definition)] = extractFields(Json(data), definition);

		return result;
	}

	Json denormalise(Json data, ref const FieldDefinition definition) inout {
		Json result = Json.emptyObject;

		result[singular(definition)] = extractFields(data, definition);

		return result;
	}

	private Json extractFields(Json data, ref const FieldDefinition definition) inout {
		Json result = data;

		if(data.type == Json.Type.array) {
			return Json((cast(Json[]) data).map!(a => extractFields(a, definition)).array);
		}

		foreach(field; definition.fields) {
			string id = field.idOriginalName;

			if(id !is null)  {
				if(data[field.name].type == Json.Type.array) {
					result[field.name] = Json(data[field.name][0..$].map!(a => a[id]).array);
				} else {
					result[field.name] = data[field.name][id];
				}
			} else {
				result[field.name] = extractFields(data[field.name], field);
			}
		}

		return result;
	}

	Json normalise(string id, Json data, ref const FieldDefinition definition) inout
	{
		enforce!CrateValidationException(singular(definition) in data,
				"object type expected to be `" ~ singular(definition) ~ "`");

		foreach(field; definition.fields) {
			if(field.isId) {
				data[singular(definition)][field.name] = id;
			}
		}

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
				"field1": "Ember Hamster",
				"field2": 5
		}
	}`.parseJsonString;

	auto deserialized = serializer.normalise("ID", serialized, fields);
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

	assert("_id" in serializer.normalise("", valueSingular, fields));
}

@("Check denormalised object relations")
unittest
{
	struct TestChild
	{
		string _id;
	}

	struct TestModel
	{
		string _id;

		TestChild child;
	}

	auto fields = getFields!TestModel;
	auto serializer = new const CrateRestApiSerializer;

	TestModel test = TestModel("id1", TestChild("id2"));

	auto value = const serializer.denormalise(test.serializeToJson, fields);

	assert(value["testModel"]["child"].type == Json.Type.string);
	assert(value["testModel"]["child"] == "id2");

	value = const serializer.denormalise([test.serializeToJson], fields);

	assert(value["testModels"][0]["child"].type == Json.Type.string);
	assert(value["testModels"][0]["child"] == "id2");
}

@("Check denormalised array relations")
unittest
{
	struct TestChild
	{
		string _id;
	}

	struct TestModel
	{
		string _id;
		TestChild[] child;
	}

	auto fields = getFields!TestModel;
	auto serializer = new const CrateRestApiSerializer;

	TestModel test = TestModel("id1", [ TestChild("id2") ]);

	auto value = const serializer.denormalise(test.serializeToJson, fields);

	assert(value["testModel"]["child"][0].type == Json.Type.string);
	assert(value["testModel"]["child"][0] == "id2");
}


@("Check denormalised nested relations")
unittest
{
	struct TestRelation
	{
		string _id;
	}

	struct TestChild
	{
		TestRelation relation;
	}

	struct TestModel
	{
		string _id;
		TestChild child;
		TestChild[] childs = [ TestChild() ];
	}

	auto fields = getFields!TestModel;
	auto serializer = new const CrateRestApiSerializer;

	TestModel test = TestModel("id1");

	test.child.relation._id = "id2";
	test.childs[0].relation._id = "id3";

	auto value = const serializer.denormalise(test.serializeToJson, fields);

	assert(value["testModel"]["child"]["relation"].type == Json.Type.string);
	assert(value["testModel"]["child"]["relation"] == "id2");
	assert(value["testModel"]["childs"].length == 1);
	assert(value["testModel"]["childs"][0]["relation"] == "id3");
}
