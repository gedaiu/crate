module crate.policy.restapi;

import crate.base;
import crate.serializer.restapi;
import crate.generator.openapi;
import crate.ctfe;

import vibe.data.json;
import vibe.http.common;

import std.string, std.stdio;

class CrateRestApiPolicy : CratePolicy
{
	private
	{
		CrateRestApiSerializer _serializer;
	}

	string name() inout pure nothrow
	{
		return "Rest API";
	}

	inout(CrateSerializer) serializer() inout pure nothrow
	{
		return _serializer;
	}

	string mime() inout pure nothrow
	{
		return "application/json";
	}
}

CrateRoutes routes(T)(const CrateConfig config)
{
	CrateRoutes definedRoutes;

	definedRoutes.schemas = schemas!T;

	return definedRoutes;
}

string basePath(T)() pure
{
	enum path = "/" ~ Plural!T.toLower;

	return path;
}

ModelDefinition definition(T)() pure
{
	ModelDefinition model;

	enum FieldDefinition[] fields = getFields!T.fields;

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
	Json[string] schemas(T)()
	{
		Json[string] schemaList;

		schemaList[T.stringof ~ "Response"] = schemaResponse!T;
		schemaList[T.stringof ~ "List"] = schemaResponseList!T;
		schemaList[T.stringof ~ "Request"] = schemaRequest!T;
		schemaList[T.stringof] = schemaModel!T;
		schemaList["StringResponse"] = schemaString;

		addRelations!T(schemaList);

		return schemaList;
	}

	Json schemaString()
	{
		Json data = Json.emptyObject;
		data["type"] = "string";
		return data;
	}

	void addRelations(T)(ref Json[string] data)
	{
		void describeRelations(FieldDefinition[] fields)()
		{
			static if (fields.length == 1)
			{
				static if (fields[0].type == "BsonObjectID")
				{
					data[fields[0].type] = Json.emptyObject;
					data[fields[0].type]["type"] = "string";
				}
				else static if (!fields[0].isBasicType)
				{
					alias Type = FieldType!(__traits(getMember, T, fields[0].originalName));

					data[fields[0].type] = Json.emptyObject;
					describe!Type(data[fields[0].type]);
				}
			}
			else static if (fields.length > 1)
			{
				describeRelations!([fields[0]])();
				describeRelations!(fields[1 .. $])();
			}
		}

		enum FieldDefinition[] fields = getFields!T.fields;
		describeRelations!(fields);
	}

	Json schemaResponse(T)()
	{
		enum singular = Singular!T[0..1].toLower ~ Singular!T[1..$];

		auto data = Json.emptyObject;
		data["type"] = "object";
		data["properties"] = Json.emptyObject;
		data["properties"][singular] = Json.emptyObject;
		data["properties"][singular]["$ref"] = "#/definitions/" ~ T.stringof;

		return data;
	}

	Json schemaResponseList(T)()
	{
		enum plural = Plural!T[0..1].toLower ~ Plural!T[1..$];

		auto data = Json.emptyObject;
		data["type"] = "object";
		data["properties"] = Json.emptyObject;
		data["properties"][plural] = Json.emptyObject;
		data["properties"][plural]["type"] = "array";
		data["properties"][plural]["items"] = Json.emptyObject;
		data["properties"][plural]["items"]["$ref"] = "#/definitions/" ~ T.stringof;

		return data;
	}

	void describe(T, bool includeId = true)(ref Json data)
	{
		data["type"] = "object";
		data["properties"] = Json.emptyObject;

		void addField(FieldDefinition field)()
		{
			data["properties"][field.name] = Json.emptyObject;
			enum type = field.type.asOpenApiType;

			static if (field.isRelation)
			{
				data["properties"][field.name]["type"] = "string";
				data["properties"][field.name]["description"] = "The id of an existing `"
					~ field.type ~ "`";
			}
			else static if (type == "object")
			{
				enum refObj = "#/definitions/" ~ field.type;

				static if (field.isArray)
				{
					data["properties"][field.name]["type"] = "array";
					data["properties"][field.name]["items"] = Json.emptyObject;
					data["properties"][field.name]["items"]["$ref"] = refObj;
				}
				else
				{
					data["properties"][field.name]["$ref"] = refObj;
				}
			}
			else
			{
				static if (field.isArray)
				{
					data["properties"][field.name]["type"] = "array";
					data["properties"][field.name]["items"] = Json.emptyObject;
					data["properties"][field.name]["items"]["type"] = type;
				}
				else
				{
					data["properties"][field.name]["type"] = type;
				}

			}

			static if (!field.isOptional)
			{
				if (data["required"].type == Json.Type.undefined)
				{
					data["required"] = Json.emptyArray;
				}

				data["required"] ~= field.name;
			}
		}

		void describeFields(FieldDefinition[] fields)()
		{
			static if (fields.length == 1)
			{
				static if (fields[0].isId && !includeId)
				{
					return;
				}
				else
				{
					addField!(fields[0]);
				}
			}
			else static if (fields.length > 1)
			{
				describeFields!([fields[0]])();
				describeFields!(fields[1 .. $])();
			}
		}

		enum FieldDefinition[] fields = getFields!T.fields;
		describeFields!(fields);
	}

	Json schemaRequest(T)()
	{
		enum singular = Singular!T[0..1].toLower ~ Singular!T[1..$];

		auto data = Json.emptyObject;
		data["type"] = "object";
		data["properties"] = Json.emptyObject;
		data["properties"][singular] = Json.emptyObject;

		describe!(T, false)(data["properties"][singular]);

		return data;
	}

	Json schemaModel(T)()
	{
		auto data = Json.emptyObject;

		describe!T(data);

		return data;
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

	auto schema = schemas!TestModel.serializeToJson;


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

	auto schema = schemas!ComposedModel.serializeToJson;

	assert(schema["ComposedModel"]["type"] == "object");
	assert(schema["ComposedModel"]["properties"]["child"]["$ref"] == "#/definitions/TestModel");

	assert(schema["TestModel"]["type"] == "object");
	assert(schema["TestModel"]["properties"]["name"]["type"] == "string");
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

	auto schema = schemas!ComposedModel;

	assert(schema["ComposedModel"]["type"] == "object");
	assert(schema["ComposedModel"]["properties"]["child"]["type"] == "string");
}
