module crate.serializer.restapi;

import crate.base, crate.ctfe, crate.openapi;

import vibe.data.json;
import vibe.data.bson;

import swaggerize.definitions;

import std.meta;
import std.algorithm.searching, std.algorithm.iteration;

import std.traits, std.stdio, std.meta;

class CrateRestApiSerializer(T) : CrateSerializer!T
{
	CrateConfig!T config;

	Json serializeToData(T item)
	{
		enum fields = getFields!T;

		return item.serializeToJson;
	}

	Json serialize(T item)
	{
		Json value = Json.emptyObject;

		value[config.singular] = serializeToData(item);

		return value;
	}

	Json serialize(T[] items)
	{
		Json value = Json.emptyObject;
		value[config.plural] = Json.emptyArray;

		foreach (item; items)
		{
			value[config.plural] ~= serializeToData(item);
		}

		return value;
	}

	T deserialize(Json data)
	{
		return deserializeJson!T(data[config.singular]);
	}

	string mime()
	{
		return "application/json";
	}

	ModelDefinition definition()
	{
		ModelDefinition model;

		enum fields = getFields!T;

		foreach (index, field; fields)
		{
			model.fields[field.name] = field;

			if (field.isId)
			{
				model.idField = field.name;
			}
		}

		return model;
	}

	Json[string] schemas()
	{
		Json[string] schemaList;

		schemaList[T.stringof ~ "Response"] = schemaResponse;
		schemaList[T.stringof ~ "List"] = schemaResponseList;
		schemaList[T.stringof ~ "Request"] = schemaRequest;

		return schemaList;
	}

	private
	{
		Json schemaResponse()
		{
			auto data = Json.emptyObject;
			data["type"] = "object";
			data["properties"] = Json.emptyObject;
			data["properties"][config.singular] = Json.emptyObject;
			data["properties"][config.singular]["$ref"] = "#/definitions/" ~ T.stringof;

			return data;
		}

		Json schemaResponseList()
		{
			auto data = Json.emptyObject;
			data["type"] = "object";
			data["properties"] = Json.emptyObject;
			data["properties"][config.plural] = Json.emptyObject;
			data["properties"][config.plural]["type"] = "array";
			data["properties"][config.plural]["items"] = Json.emptyObject;
			data["properties"][config.plural]["items"]["$ref"] = "#/definitions/" ~ T.stringof;

			return data;
		}

		Json schemaRequest()
		{
			auto data = Json.emptyObject;
			data["type"] = "object";
			data["properties"] = Json.emptyObject;
			data["properties"][config.singular] = Json.emptyObject;
			data["properties"][config.singular]["type"] = "object";
			data["properties"][config.singular]["properties"] = Json.emptyObject;

			auto model = definition;

			foreach (field; model.fields)
			{
				if (!field.isId)
				{
					data["properties"][config.singular]["properties"][field.name] = Json.emptyObject;
					data["properties"][config.singular]["properties"][field.name]["type"] = field.type.asOpenApiType;

					if (!field.isOptional)
					{
						if (data["properties"][config.singular]["required"].type == Json.Type.undefined)
						{
							data["properties"][config.singular]["required"] = Json.emptyArray;
						}

						data["properties"][config.singular]["required"] ~= field.name;
					}
				}
			}

			return data;
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

	auto serializer = new CrateRestApiSerializer!TestModel();

	//test the deserialize method
	auto serialized = `{
		"testModel": {
				"id": "ID",
				"field1": "Ember Hamster",
				"field2": 5
		}
	}`.parseJsonString;

	auto deserialized = serializer.deserialize(serialized);
	assert(deserialized.id == "ID");
	assert(deserialized.field1 == "Ember Hamster");
	assert(deserialized.field2 == 5);

	//test the serialize method
	auto value = serializer.serialize(deserialized);
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

	TestModel[] deserialized = [
		TestModel("ID1", "Ember Hamster", 5), TestModel("ID2", "Ember Hamster2", 6)
	];

	//test the serialize method
	auto value = serializer.serialize(deserialized);
	assert(value["testModels"][0]["id"] == "ID1");
	assert(value["testModels"][0]["field1"] == "Ember Hamster");
	assert(value["testModels"][0]["field2"] == 5);

	assert(value["testModels"][1]["id"] == "ID2");
	assert(value["testModels"][1]["field1"] == "Ember Hamster2");
	assert(value["testModels"][1]["field2"] == 6);
}

@("Open api schema")
unittest
{
	struct TestModel
	{
		string id;

		string field1;
		int field2;
	}

	auto serializer = new CrateRestApiSerializer!TestModel();

	auto schema = serializer.schemas;

	schema.writeln;

	assert(schema["TestModelResponse"]["type"] == "object");
	assert(schema["TestModelResponse"]["properties"]["testModel"]["$ref"] == "#/definitions/TestModel");

	assert(schema["TestModelList"]["type"] == "object");
	assert(schema["TestModelList"]["properties"]["testModels"]["type"] == "array");
	assert(schema["TestModelList"]["properties"]["testModels"]["items"]["$ref"] == "#/definitions/TestModel");

	assert(schema["TestModelRequest"]["type"] == "object");
	assert(schema["TestModelRequest"]["properties"]["testModel"]["type"] == "object");
	assert(schema["TestModelRequest"]["properties"]["testModel"]["properties"]["field1"]["type"] == "string");
	assert(schema["TestModelRequest"]["properties"]["testModel"]["properties"]["field2"]["type"] == "integer");
}
