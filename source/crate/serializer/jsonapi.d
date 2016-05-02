module crate.serializer.jsonapi;

import crate.base;

import vibe.data.json;
import vibe.data.bson;

import swaggerize.definitions;
import std.meta;

import std.traits, std.stdio, std.meta;

struct FieldDescription
{
	string name;
	string[] attributes;
	string type;
	bool isBasicType;
	bool isRelation;
	bool isId;
}

template OriginalFieldType(alias F)
{
	static if (is(FunctionTypeOf!F == function))
	{

		static if (is(ReturnType!(F) == void) && arity!(F) == 1)
		{
			alias OriginalFieldType = Unqual!(ParameterTypeTuple!F);
		}
		else
		{
			alias OriginalFieldType = Unqual!(ReturnType!F);
		}

	}
	else
	{
		alias OriginalFieldType = typeof(F);
	}
}

template ArrayType(T : T[])
{
	alias ArrayType = T;
}

template FieldType(alias F)
{

	alias FT = OriginalFieldType!F;

	static if (!isSomeString!(FT) && isArray!(FT))
	{

		alias FieldType = ArrayType!(FT);
	}
	else static if (isAssociativeArray!(FT))
	{
		alias FieldType = ValueType!(FT);
	}
	else
	{
		alias FieldType = Unqual!(FT);
	}
}

/**
 * Get all attributes
 */
template GetAttributes(string name, Prototype)
{
	template GetFuncAttributes(TL...)
	{
		static if (TL.length == 1)
		{
			alias GetFuncAttributes = AliasSeq!(__traits(getAttributes, TL[0]));
		}
		else static if (TL.length > 1)
		{
			alias GetFuncAttributes = AliasSeq!(GetFuncAttributes!(TL[0 .. $ / 2]),
					GetFuncAttributes!(TL[$ / 2 .. $]));
		}
		else
		{
			alias GetFuncAttributes = AliasSeq!();
		}
	}

	static if (is(FunctionTypeOf!(ItemProperty!(Prototype, name)) == function))
	{
		static if (__traits(getOverloads, Prototype, name).length == 1)
		{
			alias GetAttributes = AliasSeq!(__traits(getAttributes,
					ItemProperty!(Prototype, name)));
		}
		else
		{
			alias GetAttributes = AliasSeq!(GetFuncAttributes!(AliasSeq!(__traits(getOverloads,
					Prototype, name))));
		}
	}
	else
	{
		alias GetAttributes = AliasSeq!(__traits(getAttributes, ItemProperty!(Prototype, name)));
	}
}

template StringOfSeq(TL...)
{
	static if (TL.length == 1)
	{
		static if (is(typeof(TL[0]) == string))
			alias StringOfSeq = AliasSeq!(TL[0]);
		else
			alias StringOfSeq = AliasSeq!(TL[0].stringof);
	}
	else static if (TL.length > 1)
	{
		alias StringOfSeq = AliasSeq!(StringOfSeq!(TL[0 .. $ / 2]), StringOfSeq!(TL[$ / 2 .. $]));
	}
	else
	{
		alias StringOfSeq = AliasSeq!();
	}
}

/**
 * Get a class property.
 *
 * Example:
 * --------------------
 * class BookItemPrototype {
 * 	@("field", "primary")
 *	ulong id;
 *
 *	@("field") string name = "unknown";
 * 	@("field") string author = "unknown";
 * }
 *
 * assert(__traits(isIntegral, ItemProperty!(BookItemPrototype, "id")) == true);
 * --------------------
 */
template ItemProperty(item, string method)
{
	static if (__traits(hasMember, item, method))
	{
		static if (__traits(getProtection, mixin("item." ~ method)).stringof[1 .. $ - 1] == "public")
		{
			alias ItemProperty = AliasSeq!(__traits(getMember, item, method));
		}
		else
		{
			alias ItemProperty = AliasSeq!();
		}
	}
	else
	{
		alias ItemProperty = AliasSeq!();
	}
}

template Join(List...)
{

	static if (List.length == 1)
	{
		enum l = List[0].stringof[1 .. $ - 1];
	}
	else static if (List.length > 1)
	{
		enum l = List[0].stringof[1 .. $ - 1] ~ ", " ~ Join!(List[1 .. $]);
	}
	else
	{
		enum l = "";
	}

	alias Join = l;
}

template IsBasicType(T)
{
	static if (isBasicType!T || is(T == string))
	{
		enum isBasicType = true;
	}
	else
	{
		enum isBasicType = false;
	}

	alias IsBasicType = isBasicType;
}

template IsRelation(T)
{
	static if (isBasicType!T || is(T == string))
	{
		enum isRelation = false;
	}
	else
	{
		static if (is(T == class) || is(T == struct))
		{
			static if (__traits(hasMember, T, "id") || __traits(hasMember, T, "_id"))
			{
				enum isRelation = true;
			}
			else
			{
				enum isRelation = false;
			}
		}
		else
		{
			enum isRelation = false;
		}
	}

	alias IsRelation = isRelation;
}

template getFields(Prototype)
{
	/**
	 * Get all the metods
	 */
	template ItemFields(FIELDS...)
	{

		static if (FIELDS.length > 1)
		{
			alias ItemFields = AliasSeq!(ItemFields!(FIELDS[0 .. $ / 2]),
					ItemFields!(FIELDS[$ / 2 .. $]));
		}
		else static if (FIELDS.length == 1)
		{

			static if (ItemProperty!(Prototype, FIELDS[0]).length == 1)
			{
				alias Type = FieldType!(ItemProperty!(Prototype, FIELDS[0]));

				static if(FIELDS[0] == "id" || FIELDS[0] == "_id") {
					enum isId = true;
				} else {
					enum isId = false;
				}

				alias ItemFields = AliasSeq!([FieldDescription(FIELDS[0], [StringOfSeq!(GetAttributes!(FIELDS[0],
						Prototype))], Type.stringof, IsBasicType!Type, IsRelation!Type, isId)]);
			}
			else
			{
				alias ItemFields = AliasSeq!();
			}
		}
		else
			alias ItemFields = AliasSeq!();
	}

	mixin("enum list = [ " ~ Join!(ItemFields!(__traits(allMembers, Prototype))) ~ " ];");

	alias getFields = list;
}

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

		void addAttributes(FieldDescription[] fields)(ref Json serialized) {
			static if(fields.length == 1) {
				static if(!fields[0].isRelation && !fields[0].isId && fields[0].type != "void") {
					enum key = fields[0].name;
					serialized["attributes"][key] = serializeToJson(__traits(getMember, item, key));
				}
			} else if(fields.length > 1) {
				addAttributes!([fields[0]])(serialized);
				addAttributes!(fields[1..$])(serialized);
			}
		}

		void addRelationships(FieldDescription[] fields)(ref Json serialized) {
			auto serializeMember(T)(T member) {
				auto serializer = new CrateJsonApiSerializer!T;
				return serializer.serialize(member);
			}

			static if(fields.length == 1) {
				static if(fields[0].isRelation && !fields[0].isId && fields[0].type != "void") {
					enum key = fields[0].name;

					serialized["relationships"][key] = serializeMember(__traits(getMember, item, key));
				}
			} else if(fields.length > 1) {
				addRelationships!([fields[0]])(serialized);
				addRelationships!(fields[1..$])(serialized);
			}
		}

		addAttributes!fields(value);
		addRelationships!fields(value);

		foreach(field; fields) {
			if(field.isId) {
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
		assert(data["data"]["type"].to!string == config.plural);

		Json normalised = data["data"]["attributes"];

		static if (hasMember!(T, "id"))
		{
			normalised["id"] = data["data"]["id"];
		}
		else if (hasMember!(T, "_id"))
		{
			normalised["_id"] = data["data"]["id"];
		}
		else
		{
			static assert(T.stringof ~ " must contain either `id` or `_id` field.");
		}

		return deserializeJson!T(normalised);
	}

	string mime()
	{
		return "application/vnd.api+json";
	}

	ModelDefinition definition()
	{
		ModelDefinition model;

		string typeString(T)()
		{
			return T.stringof;
		}

		auto fields = [staticMap!(typeString, Fields!T)];
		alias names = FieldNameTuple!T;
		T instance;

		foreach (name; names)
		{
			mixin("alias symbol = instance." ~ name ~ ";");

			if (!hasUDA!(symbol, ignore))
			{
				static if (hasUDA!(symbol, NameAttribute))
				{
					string fieldName = getUDAs!(symbol, NameAttribute)[0].name;
				}
				else
				{
					string fieldName = name;
				}

				model.fields[fieldName] = ModelType(fields[0], hasUDA!(symbol, optional));

				if (name == "id" || name == "_id")
				{
					model.idField = name;
				}
			}

			fields = fields[1 .. $];
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
					attributes["properties"][name]["type"] = "string";

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
	assert(definition.fields["id"].isComposite == false);
	assert(definition.fields["id"].isOptional == false);
	assert(definition.fields["field1"].type == "string");
	assert(definition.fields["field1"].isComposite == false);
	assert(definition.fields["field1"].isOptional == false);
	assert(definition.fields["field2"].type == "int");
	assert(definition.fields["field2"].isComposite == false);
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
		@optional @("ignore")
		{
			string _id;
		}

		TestModel child;
	}

	auto serializer = new CrateJsonApiSerializer!ComposedModel;

	auto value = ComposedModel();
	value.child.name = "test";

	auto serializedValue = serializer.serialize(value);

	assert(serializedValue.data.relationships.child.data.attributes.name == "test");
}
