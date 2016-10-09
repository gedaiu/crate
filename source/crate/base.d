module crate.base;

import vibe.data.json, vibe.http.common;

import std.string, std.traits, std.conv;

import swaggerize.definitions;

enum CrateOperation
{
	getList,
	getItem,
	addItem,
	deleteItem,
	updateItem,
	replaceItem,
	otherItem,
	other
}

struct CrateConfig
{
	bool getList = true;
	bool getItem = true;
	bool addItem = true;
	bool deleteItem = true;
	bool replaceItem = true;
	bool updateItem = true;
}

struct PathDefinition
{
	string schemaName;
	string schemaBody;
	CrateOperation operation;
}

struct CrateRoutes
{
	Json[string] schemas;
	PathDefinition[uint][HTTPMethod][string] paths;
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
	bool isArray;

	FieldDefinition[] fields;
	string singular;
	string plural;
}

struct ModelDefinition
{
	string idField;
	FieldDefinition[string] fields;
}

interface Crate(T)
{
	alias Type = T;

	static if(is(T == void)) {
		alias Conversion = Json;
	} else static if(isBuiltinType!T) {
		alias Conversion = T;
	} else {
		alias Conversion = Json;
	}

	CrateConfig config();

	Conversion[] getList();

	Conversion addItem(Conversion item);
	Conversion getItem(string id);
	void updateItem(Conversion item);
	void deleteItem(string id);
}

interface CrateSerializer
{
	inout
	{
		Json denormalise(Json[] data, ref const FieldDefinition definition);
		Json denormalise(Json data, ref const FieldDefinition definition);

		Json normalise(string id, Json data, ref const FieldDefinition definition);
	}
}

interface CratePolicy
{
	inout pure nothrow
	{
		string name();
		string mime();
		inout(CrateSerializer) serializer();
	}
}
