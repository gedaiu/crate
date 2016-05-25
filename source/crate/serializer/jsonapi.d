module crate.serializer.jsonapi;

import crate.base, crate.ctfe;
import crate.error;

import vibe.data.json;
import vibe.data.bson;

import swaggerize.definitions;

import std.meta, std.conv, std.exception;
import std.algorithm.searching, std.algorithm.iteration;
import std.traits, std.stdio, std.string;

class CrateJsonApiSerializer(T) : CrateSerializer!T
{
	private
	{
		string type;
	}

	this() inout
	{
		this.type = Plural!T.toLower;
	}

	this(string type) inout
	{
		this.type = type;
	}

	Json denormalise(Json[] data) inout {
		Json value = Json.emptyObject;

		value["data"] = Json.emptyArray;

		foreach(item; data) {
			value["data"] ~= denormalise(item)["data"];
		}

		return value;
	}

	Json denormalise(Json data) inout {

		auto id(FieldDefinition[] relationFields)
		{
			foreach(field; relationFields) {
				if(field.isId) {
					return field.originalName;
				}
			}

			assert(false, "no id defined");
		}

		void addAttributes(FieldDefinition[] fields)(ref Json serialized)
		{
			static if (fields.length == 1)
			{
				static if (!fields[0].isRelation && !fields[0].isId && fields[0].type != "void")
				{
					serialized["data"]["attributes"][fields[0].name] = data[fields[0].originalName];
				}
			}
			else static if (fields.length > 1)
			{
				addAttributes!([fields[0]])(serialized);
				addAttributes!(fields[1 .. $])(serialized);
			}
		}

		void addRelationships(FieldDefinition[] fields)(ref Json serialized) inout
		{
			static if (fields.length == 1)
			{
				static if (fields[0].isRelation && !fields[0].isId && fields[0].type != "void")
				{
					enum key = fields[0].name;
					enum idField = id(fields[0].fields);

					serialized["data"]["relationships"][key] = Json.emptyObject;
					serialized["data"]["relationships"][key]["data"] = Json.emptyObject;
					serialized["data"]["relationships"][key]["data"]["type"] = fields[0].plural.toLower;
					if(data[fields[0].originalName].type == Json.Type.object) {
						serialized["data"]["relationships"][key]["data"]["id"] = data[fields[0].originalName][idField];
					} else {
						serialized["data"]["relationships"][key]["data"]["id"] = data[fields[0].originalName];
					}
				}
			}
			else static if (fields.length > 1)
			{
				addRelationships!([fields[0]])(serialized);
				addRelationships!(fields[1 .. $])(serialized);
			}
		}

		Json value = Json.emptyObject;
		enum fields = getFields!T;
		enum idField = id(fields);

		value["data"] = Json.emptyObject;
		value["data"]["type"] = type;
		value["data"]["id"] = data[idField];
		value["data"]["attributes"] = Json.emptyObject;
		value["data"]["relationships"] = Json.emptyObject;

		addAttributes!fields(value);
		addRelationships!fields(value);

		return value;
	}

	Json normalise(Json data) inout
	{
		enforce!CrateValidationException(data["data"]["type"].to!string == type,
				"data.type expected to be `" ~ type ~ "` instead of `" ~ data["data"]["type"].to!string ~ "`");

		auto normalised = Json.emptyObject;

		void setValues(alias Fields)()
		{
			static if (Fields.length >= 1)
			{
				enum Field = Fields[0];

				static if (Field.isId)
				{
					normalised[Field.originalName] = data["data"]["id"];
				}
				else static if (Field.isRelation)
				{
					normalised[Field.originalName] =
							data["data"]["relationships"][Field.name]["data"]["id"];
				}
				else
				{
					normalised[Field.originalName] = data["data"]["attributes"][Field.name];
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

	auto deserialized = serializer.normalise(serialized);
	assert(deserialized["id"] == "ID");
	assert(deserialized["field1"] == "Ember Hamster");
	assert(deserialized["field2"] == 5);

	//test the serialize method
	auto value = serializer.denormalise(deserialized);
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

	auto deserialized = serializer.normalise(serialized);
	assert(deserialized["_id"].to!string == "570d5afa999f19d459000000");

	//test the serialize method
	auto value = serializer.denormalise(deserialized);
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
		serializer.normalise(`{
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

	auto serializedValue = serializer.denormalise(value.serializeToJson);
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

	auto serializedValue = serializer.denormalise(value.serializeToJson);

	assert(serializedValue.data.relationships.child.data["type"] == "testmodels");
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

	auto value = serializer.normalise(serializedValue);

	assert(value.child == "id2");
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

	auto value = serializer.normalise(serializedValue);

	assert(value.child.name == "test");
}

@("Check denormalised type")
unittest
{
	@("plural: Plural2")
	struct TestModel
	{
		string _id;
		string name;
	}

	@("plural: Plural1")
	struct ComposedModel
	{
		@optional
		{
			string _id;
		}

		TestModel child;
	}

	auto serializer = new CrateJsonApiSerializer!ComposedModel;
	auto value = serializer.denormalise(ComposedModel().serializeToJson);

	assert(value["data"]["type"] == "plural1");
	assert(value["data"]["relationships"]["child"]["data"]["type"] == "plural2");
}
