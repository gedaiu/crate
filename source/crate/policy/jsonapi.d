module crate.policy.jsonapi;

import crate.base;
import crate.serializer.jsonapi;
import crate.generator.openapi;
import crate.ctfe;

import vibe.data.json;
import vibe.http.common;

import std.string, std.stdio;

class CrateJsonApiPolicy : CratePolicy
{
	private
	{
		CrateSerializer _serializer = new inout CrateJsonApiSerializer;
	}

	string name() inout pure nothrow
	{
		return "Json API";
	}

	string mime() inout pure nothrow
	{
		return "application/vnd.api+json";
	}

	inout(CrateSerializer) serializer() inout pure nothrow
	{
		return _serializer;
	}
}

CrateRoutes defineRoutes(T)(const CrateJsonApiPolicy, const CrateConfig config)
{
	CrateRoutes definedRoutes;

	definedRoutes.schemas = schemas!T;
	definedRoutes.paths = config.paths!T;

	return definedRoutes;
}

string basePath(T)() pure
{
	return "/" ~ Plural!T.toLower;
}

ModelDefinition definition(T)() pure
{
	ModelDefinition model;

	enum fields = getFields!T.fields;

	static if (!is(typeof(fields) == void[]))
	{
		foreach (index, field; fields)
		{
			model.fields[field.name] = field;

			if (field.isId)
			{
				model.idField = field.name;
			}
		}
	}

	return model;
}


private
{
	PathDefinition[uint][HTTPMethod][string] paths(T)(const CrateConfig config)
	{
		PathDefinition[uint][HTTPMethod][string] selectedPaths;

		if (config.getList)
		{
			selectedPaths[basePath!T][HTTPMethod.GET][200] = PathDefinition(T.stringof ~ "List",
					"", CrateOperation.getList);
		}

		if (config.addItem)
		{
			selectedPaths[basePath!T][HTTPMethod.POST][200] = PathDefinition(T.stringof ~ "Response",
					T.stringof ~ "Request", CrateOperation.addItem);
		}

		if (config.getItem)
		{
			selectedPaths[basePath!T ~ "/:id"][HTTPMethod.GET][200] = PathDefinition(T.stringof ~ "Response",
					"", CrateOperation.getItem);
		}

		if (config.updateItem)
		{
			selectedPaths[basePath!T ~ "/:id"][HTTPMethod.PATCH][200] = PathDefinition(T.stringof ~ "Response",
					T.stringof ~ "Request", CrateOperation.updateItem);
		}

		if (config.deleteItem)
		{
			selectedPaths[basePath!T ~ "/:id"][HTTPMethod.DELETE][201] = PathDefinition("",
					"", CrateOperation.deleteItem);
		}

		return selectedPaths;
	}

	Json[string] schemas(T)()
	{
		Json[string] schemaList;

		schemaList[T.stringof ~ "Item"] = schemaItem!T;
		schemaList[T.stringof ~ "NewItem"] = schemaNewItem!T;
		schemaList[T.stringof ~ "List"] = schemaGetList!T;
		schemaList[T.stringof ~ "Response"] = schemaResponse!T;
		schemaList[T.stringof ~ "Request"] = schemaRequest!T;
		schemaList[T.stringof ~ "Attributes"] = schemaAttributes!T;
		schemaList[T.stringof ~ "Relationships"] = schemaRelationships!T;
		schemaList["StringResponse"] = schemaString;

		addRelationshipDefinitions!T(schemaList);
		addComposedDefinitions!T(schemaList);

		return schemaList;
	}

	Json schemaString()
	{
		Json data = Json.emptyObject;
		data["type"] = "string";
		return data;
	}

	Json schemaGetList(T)()
	{
		Json data = Json.emptyObject;

		data["type"] = "object";
		data["properties"] = Json.emptyObject;
		data["properties"]["data"] = Json.emptyObject;
		data["properties"]["data"]["type"] = "array";
		data["properties"]["data"]["items"] = Json.emptyObject;
		data["properties"]["data"]["items"]["$ref"] = "#/definitions/" ~ T.stringof ~ "Item";

		return data;
	}

	Json schemaItem(T)()
	{
		Json item = schemaNewItem!T;

		item["properties"]["id"] = Json.emptyObject;
		item["properties"]["id"]["type"] = "string";

		return item;
	}

	Json schemaNewItem(T)()
	{
		Json item = Json.emptyObject;

		item["type"] = "object";
		item["properties"] = Json.emptyObject;
		item["properties"]["type"] = Json.emptyObject;
		item["properties"]["type"]["type"] = "string";
		item["properties"]["attributes"] = Json.emptyObject;
		item["properties"]["attributes"]["$ref"] = "#/definitions/" ~ T.stringof ~ "Attributes";
		item["properties"]["relationships"] = Json.emptyObject;
		item["properties"]["relationships"]["$ref"] = "#/definitions/"
			~ T.stringof ~ "Relationships";

		return item;
	}

	Json schemaResponse(T)()
	{
		Json item = Json.emptyObject;

		item["type"] = "object";

		item["properties"] = Json.emptyObject;
		item["properties"]["data"] = Json.emptyObject;
		item["properties"]["data"]["$ref"] = "#/definitions/" ~ T.stringof ~ "Item";

		return item;
	}

	Json schemaRequest(T)()
	{
		Json item = Json.emptyObject;

		item["type"] = "object";

		item["properties"] = Json.emptyObject;
		item["properties"]["data"] = Json.emptyObject;
		item["properties"]["data"]["$ref"] = "#/definitions/" ~ T.stringof ~ "NewItem";

		return item;
	}

	Json schemaAttributes(T)()
	{
		Json attributes = Json.emptyObject;
		auto model = definition!(T);
		attributes["type"] = "object";
		attributes["properties"] = Json.emptyObject;

		foreach (field; model.fields)
		{
			if (!field.isId && !field.isRelation && !field.isArray)
			{
				attributes["properties"][field.name] = Json.emptyObject;
				attributes["properties"][field.name]["type"] = field.type.asOpenApiType;
			}
			else if (field.isArray)
			{
				attributes["properties"][field.name] = Json.emptyObject;
				attributes["properties"][field.name]["type"] = "array";
				attributes["properties"][field.name]["items"] = Json.emptyObject;

				if (field.isBasicType)
				{
					attributes["properties"][field.name]["items"]["type"] = field
						.type.asOpenApiType;
				}
				else
				{
					attributes["properties"][field.name]["items"]["$ref"] = "#/definitions/"
						~ field.type ~ "Model";
				}
			}

			if (!field.isId && !field.isRelation && !field.isOptional)
			{
				if (attributes["required"].type == Json.Type.undefined)
				{
					attributes["required"] = Json.emptyArray;
				}
				attributes["required"] ~= field.name;
			}
		}

		return attributes;
	}

	Json schemaRelationships(T)()
	{
		Json attributes = Json.emptyObject;
		auto model = definition!T;
		attributes["type"] = "object";
		attributes["properties"] = Json.emptyObject;

		void addRelationships(FieldDefinition[] fields)()
		{
			static if (fields.length == 1)
			{
				static if (fields[0].isRelation && !fields[0].isId)
				{
					attributes["properties"][fields[0].name] = Json.emptyObject;
					attributes["properties"][fields[0].name]["$ref"] = "#/definitions/"
						~ fields[0].type ~ "Relation";

					static if (!fields[0].isOptional)
					{
						if (attributes["required"].type == Json.Type.undefined)
						{
							attributes["required"] = Json.emptyArray;
						}

						attributes["required"] ~= fields[0].name;
					}
				}
			}
			else static if (fields.length > 1)
			{
				addRelationships!([fields[0]])();
				addRelationships!(fields[1 .. $])();
			}
		}

		enum FieldDefinition[] fields = getFields!T.fields;
		addRelationships!(fields);

		return attributes;
	}

	void addRelationshipDefinitions(T)(ref Json[string] schemaList)
	{
		void addRelationships(FieldDefinition[] fields)()
		{
			static if (fields.length == 1)
			{
				static if (fields[0].isRelation && !fields[0].isId)
				{
					enum key = fields[0].type ~ "Relation";

					schemaList[key] = Json.emptyObject;
					schemaList[key]["required"] = [Json("data")];
					schemaList[key]["properties"] = Json.emptyObject;
					schemaList[key]["properties"]["data"] = Json.emptyObject;
					schemaList[key]["properties"]["data"]["type"] = "object";
					schemaList[key]["properties"]["data"]["required"] = [Json("type"),
						Json("id")];
					schemaList[key]["properties"]["data"]["properties"] = Json.emptyObject;
					schemaList[key]["properties"]["data"]["properties"]["type"] = Json
						.emptyObject;
					schemaList[key]["properties"]["data"]["properties"]["type"]["type"] = "string";
					schemaList[key]["properties"]["data"]["properties"]["id"] = Json
						.emptyObject;
					schemaList[key]["properties"]["data"]["properties"]["id"]["type"] = "string";

					schemaList[key]["type"] = "object";
				}
			}
			else static if (fields.length > 1)
			{
				addRelationships!([fields[0]])();
				addRelationships!(fields[1 .. $])();
			}
		}

		enum FieldDefinition[] fields = getFields!T.fields;
		addRelationships!(fields);
	}

	void addComposedDefinitions(T)(ref Json[string] schemaList)
	{
		void describe(FieldDefinition[] fields, U)(ref Json schema)
		{
			static if (fields.length == 1)
			{
				if ("properties" !in schema)
				{
					schema["properties"] = Json.emptyObject;
				}

				enum key = fields[0].name;

				static if (fields[0].isBasicType)
				{
					schema["properties"][key] = Json.emptyObject;
					schema["properties"][key]["type"] = asOpenApiType(fields[0].type);
				}
				else static if (!fields[0].isRelation && !fields[0].isBasicType)
				{
					alias Type = FieldType!(__traits(getMember, U, fields[0].originalName));
					enum name = fields[0].type ~ "Model";

					if (name !in schemaList)
					{
						schemaList[name] = Json.emptyObject;
					}

					schema["properties"][key] = Json.emptyObject;
					schema["properties"][key]["$ref"] = "#/definitions/"
						~ fields[0].type ~ "Model";

					enum FieldDefinition[] fields = getFields!Type.fields;
					describe!(fields, Type)(schemaList[name]);
				}
			}
			else static if (fields.length > 1)
			{
				describe!([fields[0]], U)(schema);
				describe!(fields[1 .. $], U)(schema);
			}
		}

		void addComposed(FieldDefinition[] fields)()
		{
			static if (fields.length == 1)
			{
				static if (!fields[0].isRelation && !fields[0].isBasicType)
				{
					alias Type = FieldType!(__traits(getMember, T, fields[0].originalName));
					enum key = fields[0].type ~ "Model";

					schemaList[key] = Json.emptyObject;

					static if (fields[0].type == "BsonObjectID")
					{
						schemaList[key]["type"] = "string";
					}
					else
					{
						schemaList[key]["type"] = "object";
						enum fields = getFields!Type.fields;
						describe!(fields, Type)(schemaList[key]);
					}
				}
			}
			else static if (fields.length > 1)
			{
				addComposed!([fields[0]])();
				addComposed!(fields[1 .. $])();
			}
		}

		enum FieldDefinition[] fields = getFields!T.fields;
		addComposed!(fields);
	}
}






version (unittest)
{
	struct TestModel
	{
		string _id;
	}
}

@("It should have the right mime")
unittest
{
	auto policy = new const CrateJsonApiPolicy();
	assert(policy.mime == "application/vnd.api+json");
}

@("Check Json api definition")
unittest
{
	struct TestModel
	{
		string id;

		string field1;
		int field2;

		@ignore int field3;
	}

	auto definition = definition!TestModel;

	assert(definition.idField == "id");
	assert(definition.fields["id"].type == "string");
	assert(definition.fields["id"].isBasicType);
	assert(definition.fields["id"].isOptional == false);
	assert(definition.fields["field1"].type == "string");
	assert(definition.fields["field1"].isBasicType);
	assert(definition.fields["field1"].isOptional == false);
	assert(definition.fields["field2"].type == "int");
	assert(definition.fields["field2"].isBasicType);
	assert(definition.fields["field2"].isOptional == false);

	assert("field3" !in definition.fields);
}

@("Check optional field definition")
unittest
{
	struct TestModel
	{
		string _id;

		@optional string optionalField;
	}

	auto definition = definition!TestModel;
	assert(definition.fields["optionalField"].isOptional);
}

@("Use the custom property names")
unittest
{
	struct TestModel
	{
		string _id;

		@name("optional-field")
		string optionalField;
	}

	auto definition = definition!TestModel;

	assert("optional-field" in definition.fields);
	assert("optionalField" !in definition.fields);
}

@("Check for the id field")
unittest
{
	import vibe.data.bson;

	struct TestModel
	{
		BsonObjectID _id;
	}

	auto definition = definition!TestModel;
	auto schema = schemas!TestModel.serializeToJson;

	assert(definition.idField == "_id");
	assert(schema["BsonObjectIDModel"]["type"] == "string");
}
