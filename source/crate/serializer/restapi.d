module crate.serializer.restapi;

import crate.base, crate.ctfe, crate.generator.openapi;

import vibe.data.json;
import vibe.data.bson;

import swaggerize.definitions;

import std.meta, std.string;
import std.algorithm.searching, std.algorithm.iteration;

import std.traits, std.stdio, std.meta;

class CrateRestApiSerializer(T) : CrateSerializer!T
{
	protected
	{
		CrateConfig!T _config;
	}

	@property
	{
		CrateConfig!T config() inout
		{
			return _config;
		}

		string basePath()
		{
			return "/" ~ config.plural.toLower;
		}

		CrateRoutes routes()
		{
			CrateRoutes definedRoutes;

			definedRoutes.schemas = schemas;

			return definedRoutes;
		}
	}

	this()
	{
		this(CrateConfig!T());
	}

	this(CrateConfig!T config)
	{
		_config = config;
	}

	Json serializeToData(T item) inout
	{
		enum fields = getFields!T;

		return item.serializeToJson;
	}

	Json serialize(T item, Json replace = Json.emptyObject) inout
	{
		Json value = Json.emptyObject;

		value[config.singular] = serializeToData(item);

		return value;
	}

	Json serialize(T[] items) inout
	{
		Json value = Json.emptyObject;
		value[config.plural] = Json.emptyArray;

		foreach (item; items)
		{
			value[config.plural] ~= serializeToData(item);
		}

		return value;
	}

	T deserialize(Json data) inout
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

	private
	{
		Json[string] schemas()
		{
			Json[string] schemaList;

			schemaList[T.stringof ~ "Response"] = schemaResponse;
			schemaList[T.stringof ~ "List"] = schemaResponseList;
			schemaList[T.stringof ~ "Request"] = schemaRequest;
			schemaList[T.stringof] = schemaModel;

			return schemaList;
		}

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

		void schemaObject(T, bool includeId = true)(ref Json data)
		{
			data["type"] = "object";
			data["properties"] = Json.emptyObject;

			void addFields(FieldDefinition[] fields)()
			{
				static if (fields.length == 1)
				{
					static if (fields[0].isId && !includeId)
					{
						return;
					}
					else static if (fields[0].isRelation)
					{
						data["properties"][fields[0].name] = Json.emptyObject;
						data["properties"][fields[0].name]["type"] = "string";
						data["properties"][fields[0].name]["description"] = "The id of an existing `"
							~ fields[0].type ~ "`";
					}
					else
					{
						enum type = fields[0].type.asOpenApiType;
						data["properties"][fields[0].name] = Json.emptyObject;
						data["properties"][fields[0].name]["type"] = type;

						static if (type == "object")
						{
							alias U = typeof(__traits(getMember, T, fields[0].originalName));
							data["properties"][fields[0].name]["properties"] = Json.emptyObject;
							schemaObject!U(data["properties"][fields[0].name]);
						}

						if (!fields[0].isOptional)
						{
							if (data["required"].type == Json.Type.undefined)
							{
								data["required"] = Json.emptyArray;
							}

							data["required"] ~= fields[0].name;
						}
					}
				}
				else if (fields.length > 1)
				{
					addFields!([fields[0]])();
					addFields!(fields[1 .. $])();
				}
			}

			addFields!(getFields!T);
		}

		Json schemaRequest()
		{
			auto data = Json.emptyObject;
			data["type"] = "object";
			data["properties"] = Json.emptyObject;
			data["properties"][config.singular] = Json.emptyObject;

			schemaObject!(T, false)(data["properties"][config.singular]);

			return data;
		}

		Json schemaModel()
		{
			auto data = Json.emptyObject;

			schemaObject!T(data);

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

	assert(schema["TestModelResponse"]["type"] == "object");
	assert(
			schema["TestModelResponse"]["properties"]["testModel"]["$ref"] == "#/definitions/TestModel");

	assert(schema["TestModelList"]["type"] == "object");
	assert(schema["TestModelList"]["properties"]["testModels"]["type"] == "array");
	assert(
			schema["TestModelList"]["properties"]["testModels"]["items"]["$ref"] == "#/definitions/TestModel");

	assert(schema["TestModelRequest"]["type"] == "object");
	assert(schema["TestModelRequest"]["properties"]["testModel"]["type"] == "object");
	assert(
			schema["TestModelRequest"]["properties"]["testModel"]["properties"]["id"].type
			== Json.Type.undefined);
	assert(
			schema["TestModelRequest"]["properties"]["testModel"]["properties"]["field1"]["type"] == "string");
	assert(
			schema["TestModelRequest"]["properties"]["testModel"]["properties"]["field2"]["type"] == "integer");

	assert(schema["TestModel"]["type"] == "object");
	assert(schema["TestModel"]["properties"]["id"]["type"] == "string");
	assert(schema["TestModel"]["properties"]["field1"]["type"] == "string");
	assert(schema["TestModel"]["properties"]["field2"]["type"] == "integer");
}

@("Open api schema with detailed objects")
unittest
{
	struct TestModel
	{
		string name;
	}

	struct ComposedModel
	{
		@optional
		{
			string _id;
		}

		TestModel child;
	}

	auto serializer = new CrateRestApiSerializer!ComposedModel;

	auto schema = serializer.schemas;

	assert(schema["ComposedModel"]["type"] == "object");
	assert(schema["ComposedModel"]["properties"]["child"]["type"] == "object");
	assert(schema["ComposedModel"]["properties"]["child"]["properties"]["name"]["type"] == "string");
}

@("Open api schema with relations")
unittest
{
	struct TestModel
	{
		string id;
		string name;
	}

	struct ComposedModel
	{
		@optional
		{
			string _id;
		}

		TestModel child;
	}

	auto serializer = new CrateRestApiSerializer!ComposedModel;

	auto schema = serializer.schemas;

	assert(schema["ComposedModel"]["type"] == "object");
	assert(schema["ComposedModel"]["properties"]["child"]["type"] == "string");
}
