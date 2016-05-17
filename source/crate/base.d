module crate.base;

import vibe.data.json;

import std.string, std.traits, std.conv;

import swaggerize.definitions;

struct CrateConfig(T)
{
	enum string singular = T.stringof[0..1].toLower ~ T.stringof[1..$];
	enum string plural = T.stringof[0..1].toLower ~ T.stringof[1..$] ~ "s";

	bool getList = true;
	bool getItem = true;
	bool addItem = true;
	bool deleteItem = true;
	bool updateItem = true;
}

struct FieldDefinition
{
	string name;
	string originalName;

	string[] attributes;
	string type;
	bool isBasicType;
	bool isRelation;
	bool isId;
	bool isOptional;
}

struct ModelDefinition
{
	string idField;
	FieldDefinition[string] fields;
}

interface Crate(T)
{
	T[] getList();

	T addItem(T item);
	T getItem(string id);
	T editItem(string id, Json fields);
	void deleteItem(string id);
}

interface CrateSerializer(T)
{
	Json serialize(T item);
	Json serialize(T[] items);

	T deserialize(Json data);

	string mime();
	ModelDefinition definition();
	Json[string] schemas();
}
