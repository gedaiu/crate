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

	CrateConfig config();

	Json[] getList();

	Json addItem(Json item);
	Json getItem(string id);
	Json editItem(string id, Json fields);
	void updateItem(Json item);
	void deleteItem(string id);
}

interface CrateSerializer
{
	inout
	{
		Json denormalise(Json[] data, ref const FieldDefinition definition);
		Json denormalise(Json data, ref const FieldDefinition definition);

		Json normalise(Json data, ref const FieldDefinition definition);
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
