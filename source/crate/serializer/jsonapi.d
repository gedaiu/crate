module crate.serializer.jsonapi;

import crate.base, crate.ctfe;
import crate.error;

import vibe.data.json;
import vibe.data.bson;

import swaggerize.definitions;

import std.meta, std.conv, std.exception;
import std.algorithm.searching, std.algorithm.iteration;
import std.traits, std.stdio, std.string;

class CrateJsonApiSerializer : CrateSerializer
{
	Json denormalise(Json[] data, ref const FieldDefinition definition) inout {
		Json value = Json.emptyObject;

		value["data"] = Json.emptyArray;

		foreach(item; data) {
			value["data"] ~= denormalise(item, definition)["data"];
		}

		return value;
	}

	Json denormalise(Json data, ref const FieldDefinition definition) inout {
		auto id(const FieldDefinition[] relationFields)
		{
			foreach(field; relationFields) {
				if(field.isId) {
					return field.originalName;
				}
			}

			assert(false, "no id defined");
		}

		void addAttributes(ref Json serialized, const FieldDefinition[] fields)
		{
			foreach(field; fields) {
				if (!field.isRelation && !field.isId && field.type != "void")
				{
					serialized["data"]["attributes"][field.name] = data[field.originalName];
				}
			}
		}

		void addRelationships(ref Json serialized, const FieldDefinition[] fields)
		{
			foreach(field; fields)
			{
				if(field.isRelation && !field.isId && field.type != "void") {
					auto key = field.name;
					auto idField = id(field.fields);

					serialized["data"]["relationships"][key] = Json.emptyObject;

					if (field.isArray)
					{
						serialized["data"]["relationships"][key]["data"] = Json.emptyArray;

						foreach(item; data[field.originalName]) {
							auto obj = Json.emptyObject;

							obj["type"] = field.plural.toLower;

							if(item.type == Json.Type.object) {
								obj["id"] = item[idField];
							} else {
								obj["id"] = item;
							}

							serialized["data"]["relationships"][key]["data"] ~= obj;
						}
					}
					else
					{
						serialized["data"]["relationships"][key]["data"] = Json.emptyObject;
						serialized["data"]["relationships"][key]["data"]["type"] = field.plural.toLower;
						if(data[field.originalName].type == Json.Type.object) {
							serialized["data"]["relationships"][key]["data"]["id"] = data[field.originalName][idField];
						} else {
							serialized["data"]["relationships"][key]["data"]["id"] = data[field.originalName];
						}
					}
				}
			}
		}

		Json value = Json.emptyObject;
		auto idField = id(definition.fields);

		value["data"] = Json.emptyObject;
		value["data"]["type"] = type(definition);
		value["data"]["id"] = data[idField];
		value["data"]["attributes"] = Json.emptyObject;
		value["data"]["relationships"] = Json.emptyObject;
		addAttributes(value, definition.fields);
		addRelationships(value, definition.fields);

		return value;
	}

	Json normalise(Json data, ref const FieldDefinition definition) inout
	{
		enforce!CrateValidationException(data["data"]["type"].to!string == type(definition),
				"data.type expected to be `" ~ type(definition) ~ "` instead of `" ~ data["data"]["type"].to!string ~ "`");

		auto normalised = Json.emptyObject;

		void setValues(const FieldDefinition[] fields)
		{
			foreach(field; fields)
			{
				if (field.isId)
				{
					normalised[field.originalName] = data["data"]["id"];
				}
				else if (field.isArray && field.isRelation)
				{
					normalised[field.originalName] = Json.emptyArray;

					foreach(value; data["data"]["relationships"][field.name]["data"]) {
						normalised[field.originalName] ~= value["id"];
					}
				}
				else if (field.isArray)
				{
					normalised[field.originalName] = data["data"]["attributes"][field.name];
				}
				else if (field.isRelation)
				{
					normalised[field.originalName] =
							data["data"]["relationships"][field.name]["data"]["id"];
				}
				else
				{
					normalised[field.originalName] = data["data"]["attributes"][field.name];
				}
			}
		}

		setValues(definition.fields);

		return normalised;
	}


	private inout pure {
		string type(const FieldDefinition definition)  {
			return definition.plural.toLower;
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
	}

	auto serializer = new const CrateJsonApiSerializer;

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

	auto fields = getFields!TestModel;

	auto deserialized = serializer.normalise(serialized, fields);
	assert(deserialized["id"] == "ID");
	assert(deserialized["field1"] == "Ember Hamster");
	assert(deserialized["field2"] == 5);

	//test the serialize method
	auto value = serializer.denormalise(deserialized, fields);
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

	auto serializer = new const CrateJsonApiSerializer;

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

	auto fields = getFields!TestModel;

	auto deserialized = serializer.normalise(serialized, fields);
	assert(deserialized["_id"].to!string == "570d5afa999f19d459000000");

	//test the serialize method
	auto value = serializer.denormalise(deserialized, fields);
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

	auto serializer = new const CrateJsonApiSerializer;
	auto fields = getFields!TestModel;

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
		}`.parseJsonString, fields);
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

	auto fields = getFields!ComposedModel;
	auto serializer = new const CrateJsonApiSerializer;

	auto value = ComposedModel();
	value.child.name = "test";

	auto serializedValue = serializer.denormalise(value.serializeToJson, fields);
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

	auto fields = getFields!ComposedModel;
	auto serializer = new const CrateJsonApiSerializer;

	auto value = ComposedModel();
	value._id = "id1";
	value.child.name = "test";
	value.child.id = "id2";

	auto serializedValue = serializer.denormalise(value.serializeToJson, fields);

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

	auto fields = getFields!ComposedModel;
	auto serializer = new const CrateJsonApiSerializer;

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

	auto value = serializer.normalise(serializedValue, fields);

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

	auto fields = getFields!ComposedModel;
	auto serializer = new const CrateJsonApiSerializer;

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

	auto value = serializer.normalise(serializedValue, fields);

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

	auto fields = getFields!ComposedModel;
	auto serializer = new const CrateJsonApiSerializer;
	auto value = serializer.denormalise(ComposedModel().serializeToJson, fields);

	assert(value["data"]["type"] == "plural1");
	assert(value["data"]["relationships"]["child"]["data"]["type"] == "plural2");

	assert("child" in serializer.normalise(value, fields));
}

@("Relation list")
unittest
{
	struct TestModel
	{
		string _id;
		string name;
	}

	struct ComposedModel
	{
		@optional
		{
			string _id;
		}

		TestModel[] child;
	}

	auto serializer = new const CrateJsonApiSerializer;
	auto value = ComposedModel();
	value.child ~= TestModel("1");
	value.child ~= TestModel("2");

	auto fields = getFields!ComposedModel;
	auto apiValue = serializer.denormalise(value.serializeToJson, fields);

	assert(apiValue["data"]["relationships"]["child"]["data"].type == Json.Type.array);
	assert(apiValue["data"]["relationships"]["child"]["data"].length == 2);
	assert(apiValue["data"]["relationships"]["child"]["data"][0]["id"] == "1");
	assert(apiValue["data"]["relationships"]["child"]["data"][0]["type"] == "testmodels");
	assert(apiValue["data"]["relationships"]["child"]["data"][1]["id"] == "2");

	auto normalisedValue = serializer.normalise(apiValue, fields);

	assert(normalisedValue["child"].type == Json.Type.array);
	assert(normalisedValue["child"].length == 2);
	assert(normalisedValue["child"][0] == "1");
	assert(normalisedValue["child"][1] == "2");
}
