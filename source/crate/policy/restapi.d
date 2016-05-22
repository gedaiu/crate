module crate.policy.restapi;

import crate.base;
import crate.serializer.restapi;
import crate.generator.openapi;
import crate.ctfe;

import vibe.data.json;
import vibe.http.common;

import std.string;

class CrateRestApiPolicy(T) : CratePolicy!T
{
  private
  {
    CrateRestApiSerializer!T _serializer;
    CrateConfig!T _config;
  }

  this(CrateConfig!T config = CrateConfig!T()) inout
  {
    this._config = config;
    this._serializer = new inout CrateRestApiSerializer!T(config.singular, config.plural);
  }

	inout(CrateConfig!T) config() inout pure
	{
		return _config;
	}

  inout(CrateSerializer!T) serializer() inout pure
	{
		return _serializer;
	}

	string basePath() inout pure
	{
		return "/" ~ config.plural.toLower;
	}

	CrateRoutes routes() inout
	{
		CrateRoutes definedRoutes;

		definedRoutes.schemas = schemas;

		return definedRoutes;
	}

	string mime() inout pure nothrow
	{
		return "application/json";
	}

	ModelDefinition definition() inout pure
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

	private inout
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



@("Open api schema")
unittest
{
	struct TestModel
	{
		string id;

		string field1;
		int field2;
	}

	auto policy = new CrateRestApiPolicy!TestModel();

	auto schema = policy.schemas;

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

	auto policy = new CrateRestApiPolicy!ComposedModel;

	auto schema = policy.schemas;

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

	auto policy = new CrateRestApiPolicy!ComposedModel;

	auto schema = policy.schemas;

	assert(schema["ComposedModel"]["type"] == "object");
	assert(schema["ComposedModel"]["properties"]["child"]["type"] == "string");
}
