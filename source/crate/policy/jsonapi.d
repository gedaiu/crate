module crate.policy.jsonapi;

import crate.base;
import crate.serializer.jsonapi;
import crate.generator.openapi;
import crate.ctfe;

import vibe.data.json;
import vibe.http.common;

import std.string, std.stdio;

class CrateJsonApiPolicy(T) : CratePolicy!T
{
	private
	{
		CrateJsonApiSerializer!T _serializer;
		CrateConfig!T _config;
	}

	this(CrateConfig!T config = CrateConfig!T()) inout
	{
		this._config = config;
		this._serializer = new inout CrateJsonApiSerializer!T(config.plural.toLower.dup);
	}

	string mime() inout pure nothrow
	{
		return "application/vnd.api+json";
	}

	inout(CrateSerializer!T) serializer() inout pure
	{
		return _serializer;
	}

	ModelDefinition definition() inout pure
	{
		ModelDefinition model;

		enum fields = getFields!T;

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

	inout(CrateConfig!T) config() inout pure
	{
		return _config;
	}

	string basePath() inout pure
	{
		return "/" ~ config.plural.toLower;
	}

	CrateRoutes routes() inout
	{
		CrateRoutes definedRoutes;

		definedRoutes.schemas = schemas;
		definedRoutes.paths = paths;

		return definedRoutes;
	}

	private inout
	{
		PathDefinition[uint][HTTPMethod][string] paths()
		{
			PathDefinition[uint][HTTPMethod][string] selectedPaths;

			if (config.getList)
			{
				selectedPaths[basePath][HTTPMethod.GET][200] = PathDefinition(T.stringof ~ "List",
						"", CrateOperation.getList);
			}

			if (config.addItem)
			{
				selectedPaths[basePath][HTTPMethod.POST][200] = PathDefinition(T.stringof ~ "Response",
						T.stringof ~ "Request", CrateOperation.addItem);
			}

			if (config.getItem)
			{
				selectedPaths[basePath ~ "/:id"][HTTPMethod.GET][200] = PathDefinition(T.stringof ~ "Response",
						"", CrateOperation.getItem);
			}

			if (config.updateItem)
			{
				selectedPaths[basePath ~ "/:id"][HTTPMethod.PATCH][200] = PathDefinition(T.stringof ~ "Response",
						T.stringof ~ "Request", CrateOperation.updateItem);
			}

			if (config.deleteItem)
			{
				selectedPaths[basePath ~ "/:id"][HTTPMethod.DELETE][201] = PathDefinition("",
						"", CrateOperation.deleteItem);
			}

			return selectedPaths;
		}

		Json[string] schemas()
		{
			Json[string] schemaList;

			schemaList[T.stringof ~ "Item"] = schemaItem;
			schemaList[T.stringof ~ "NewItem"] = schemaNewItem;
			schemaList[T.stringof ~ "List"] = schemaGetList;
			schemaList[T.stringof ~ "Response"] = schemaResponse;
			schemaList[T.stringof ~ "Request"] = schemaRequest;
			schemaList[T.stringof ~ "Attributes"] = schemaAttributes;
			schemaList[T.stringof ~ "Relationships"] = schemaRelationships;
			schemaList["StringResponse"] = schemaString;

			addRelationshipDefinitions(schemaList);
			addComposedDefinitions(schemaList);

			return schemaList;
		}

		Json schemaString()
		{
			Json data = Json.emptyObject;
			data["type"] = "string";
			return data;
		}

		Json schemaGetList()
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

		Json schemaItem()
		{
			Json item = schemaNewItem;

			item["properties"]["id"] = Json.emptyObject;
			item["properties"]["id"]["type"] = "string";

			return item;
		}

		Json schemaNewItem()
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

		Json schemaResponse()
		{
			Json item = Json.emptyObject;

			item["type"] = "object";

			item["properties"] = Json.emptyObject;
			item["properties"]["data"] = Json.emptyObject;
			item["properties"]["data"]["$ref"] = "#/definitions/" ~ T.stringof ~ "Item";

			return item;
		}

		Json schemaRequest()
		{
			Json item = Json.emptyObject;

			item["type"] = "object";

			item["properties"] = Json.emptyObject;
			item["properties"]["data"] = Json.emptyObject;
			item["properties"]["data"]["$ref"] = "#/definitions/" ~ T.stringof ~ "NewItem";

			return item;
		}

		Json schemaAttributes()
		{
			Json attributes = Json.emptyObject;
			auto model = definition;
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

		Json schemaRelationships()
		{
			Json attributes = Json.emptyObject;
			auto model = definition;
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

			addRelationships!(getFields!T);

			return attributes;
		}

		void addRelationshipDefinitions(ref Json[string] schemaList)
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

			addRelationships!(getFields!T);
		}

		void addComposedDefinitions(ref Json[string] schemaList)
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

						describe!(getFields!Type, Type)(schemaList[name]);
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
							describe!(getFields!Type, Type)(schemaList[key]);
						}
					}
				}
				else static if (fields.length > 1)
				{
					addComposed!([fields[0]])();
					addComposed!(fields[1 .. $])();
				}
			}

			addComposed!(getFields!T);
		}
	}
}

version (unittest)
{
	struct TestModel
	{
		string _id;
	}
}

@("it should have the right mime")
unittest
{
	auto policy = new CrateJsonApiPolicy!TestModel();
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

	auto policy = new CrateJsonApiPolicy!TestModel();

	auto definition = policy.definition;

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

	auto policy = new CrateJsonApiPolicy!TestModel();

	auto definition = policy.definition;
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

	auto policy = new CrateJsonApiPolicy!TestModel();

	auto definition = policy.definition;

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

	auto policy = new CrateJsonApiPolicy!TestModel();

	auto definition = policy.definition;
	auto schema = policy.schemas.serializeToJson;

	assert(definition.idField == "_id");
	assert(schema["BsonObjectIDModel"]["type"] == "string");
}
