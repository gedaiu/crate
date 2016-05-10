module crate.serializer.jsonapi;

import crate.base, crate.ctfe, crate.openapi;

import vibe.data.json;
import vibe.data.bson;

import swaggerize.definitions;

import std.meta;
import std.algorithm.searching, std.algorithm.iteration;

import std.traits, std.stdio, std.meta;

class CrateJsonApiSerializer(T) : CrateSerializer!T
{
	CrateConfig!T config;

	Json serializeToData(T item)
	{
		enum fields = getFields!T;

		Json original = item.serializeToJson;
		auto value = Json.emptyObject;

		value["type"] = config.plural;
		value["attributes"] = Json.emptyObject;
		value["relationships"] = Json.emptyObject;

		void addAttributes(FieldDefinition[] fields)(ref Json serialized)
		{
			static if (fields.length == 1)
			{
				static if (!fields[0].isRelation && !fields[0].isId && fields[0].type != "void")
				{
					enum key = fields[0].originalName;
					serialized["attributes"][key] = serializeToJson(__traits(getMember, item, key));
				}
			}
			else if (fields.length > 1)
			{
				addAttributes!([fields[0]])(serialized);
				addAttributes!(fields[1 .. $])(serialized);
			}
		}

		void addRelationships(FieldDefinition[] fields)(ref Json serialized)
		{
			auto serializeMember(T)(T member)
			{
				auto serializer = new CrateJsonApiSerializer!T;
				return serializer.serialize(member);
			}

			static if (fields.length == 1)
			{
				static if (fields[0].isRelation && !fields[0].isId && fields[0].type != "void")
				{
					enum key = fields[0].name;

					serialized["relationships"][key] = serializeMember(__traits(getMember,
							item, key));
				}
			}
			else if (fields.length > 1)
			{
				addRelationships!([fields[0]])(serialized);
				addRelationships!(fields[1 .. $])(serialized);
			}
		}

		addAttributes!fields(value);
		addRelationships!fields(value);

		foreach (field; fields)
		{
			if (field.isId)
			{
				value["id"] = original[field.name];
			}
		}

		return value;
	}

	Json serialize(T item)
	{
		Json value = Json.emptyObject;

		value["data"] = serializeToData(item);

		return value;
	}

	Json serialize(T[] items)
	{
		Json value = Json.emptyObject;
		value["data"] = Json.emptyArray;

		foreach (item; items)
		{
			value["data"] ~= serializeToData(item);
		}

		return value;
	}

	T deserialize(Json data)
	{
		return deserializeJson!T(normalise(data));
	}

	Json normalise(Json data)
	{
		assert(data["data"]["type"].to!string == config.plural);

		auto normalised = Json.emptyObject;

		void setValues(alias Fields)()
		{
			static if (Fields.length >= 1)
			{
				enum Field = Fields[0];

				static if (Field.isId)
				{
					normalised[Field.name] = data["data"]["id"];
				}
				else static if (Field.isRelation)
				{
					alias RelationType = typeof(__traits(getMember, T, Field.name));
					auto relationDeserializer = new CrateJsonApiSerializer!RelationType;

					normalised[Field.name] = relationDeserializer.normalise(data["data"]["relationships"][Field.name]);
				} else {
					normalised[Field.name] = data["data"]["attributes"][Field.name];
				}
			}

			static if (Fields.length > 1)
			{
				setValues!(Fields[1 .. $]);
			}
		}

		setValues!(getFields!T);

		return normalised;
	}

	string mime()
	{
		return "application/vnd.api+json";
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

		schemaList[T.stringof ~ "Item"] = schemaItem;
		schemaList[T.stringof ~ "NewItem"] = schemaNewItem;
		schemaList[T.stringof ~ "List"] = schemaGetList;
		schemaList[T.stringof ~ "Response"] = schemaResponse;
		schemaList[T.stringof ~ "Request"] = schemaRequest;
		schemaList[T.stringof ~ "Attributes"] = schemaAttributes;

		return schemaList;
	}

	private
	{
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
			attributes["required"] = Json.emptyArray;
			attributes["properties"] = Json.emptyObject;

			foreach (string name, field; model.fields)
			{
				if (name != model.idField)
				{
					attributes["properties"][name] = Json.emptyObject;
					attributes["properties"][name]["type"] = field.type.asOpenApiType;

					if (!field.isOptional)
					{
						attributes["required"] ~= name;
					}
				}
			}

			return attributes;
		}
	}
}

unittest
{
	struct TestModel
	{
		string id;

		string field1;
		int field2;

		@ignore int field3;
	}

	auto serializer = new CrateJsonApiSerializer!TestModel();

	auto definition = serializer.definition;
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

unittest
{
	struct TestModel
	{
		string _id;
	}

	auto serializer = new CrateJsonApiSerializer!TestModel();

	auto definition = serializer.definition;
	assert(definition.idField == "_id");
}

unittest
{
	struct TestModel
	{
		string _id;

		@optional string optionalField;
	}

	auto serializer = new CrateJsonApiSerializer!TestModel();

	auto definition = serializer.definition;
	assert(definition.fields["optionalField"].isOptional);
}

unittest
{
	struct TestModel
	{
		string _id;

		@name("optional-field")
		string optionalField;
	}

	auto serializer = new CrateJsonApiSerializer!TestModel();

	auto definition = serializer.definition;

	assert("optional-field" in definition.fields);
	assert("optionalField" !in definition.fields);
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

unittest
{
	struct TestModel
	{
		string name;
	}

	struct ComposedModel
	{
		string _id;

		TestModel child;
	}

	auto serializer = new CrateJsonApiSerializer!ComposedModel;

	auto value = ComposedModel();
	value.child.name = "test";

	auto serializedValue = serializer.serialize(value);
	assert(serializedValue.data.attributes.child.name == "test");
}

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

	auto serializer = new CrateJsonApiSerializer!ComposedModel;

	auto value = ComposedModel();
	value._id = "id1";
	value.child.name = "test";
	value.child.id = "id2";

	auto serializedValue = serializer.serialize(value);

	assert(serializedValue.data.relationships.child.data.attributes.name == "test");
	assert(serializedValue.data.relationships.child.data.id == "id2");
	assert(serializedValue.data.id == "id1");
}

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

	auto serializer = new CrateJsonApiSerializer!ComposedModel;

	auto serializedValue = q{{
		"data": {
			"attributes": {},
			"relationships": {
				"child": {
					"data": {
						"attributes": {
							"name": "test"
						},
						"relationships": {},
						"type": "testmodels",
						"id": "id2"
					}
				}
			},
			"type": "composedmodels",
			"id": "id1"
		}
	}}.parseJsonString;

	auto value = serializer.deserialize(serializedValue);

	assert(value.child.name == "test");
}

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

	auto serializer = new CrateJsonApiSerializer!ComposedModel;

	auto serializedValue = q{{
		"data": {
			"attributes": {
				"child": {
					"name": "test"
				}
			},
			"type": "composedmodels",
			"id": "id1"
		}
	}}.parseJsonString;

	auto value = serializer.deserialize(serializedValue);

	assert(value.child.name == "test");
}
