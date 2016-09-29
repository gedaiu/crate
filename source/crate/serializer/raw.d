module crate.serializer.raw;

import crate.base, crate.ctfe;
import crate.error;

import vibe.data.json;
import vibe.data.bson;

import swaggerize.definitions;

import std.meta, std.conv, std.exception;
import std.algorithm.searching, std.algorithm.iteration;
import std.traits, std.stdio, std.string;

class RawSerializer : CrateSerializer
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

	Json normalise(string id, Json data, ref const FieldDefinition definition) inout
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
