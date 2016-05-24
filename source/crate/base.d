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

struct CrateConfig(T)
{
	string singular = T.stringof[0 .. 1].toLower ~ T.stringof[1 .. $];
	string plural = T.stringof[0 .. 1].toLower ~ T.stringof[1 .. $] ~ "s";

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
}

struct ModelDefinition
{
	string idField;
	FieldDefinition[string] fields;
}

interface Crate
{
	Json[] getList();

	Json addItem(Json item);
	Json getItem(string id);
	Json editItem(string id, Json fields);
	void updateItem(Json item);
	void deleteItem(string id);
}

interface CrateSerializer(T)
{
	inout
	{
		Json denormalise(Json[] data);
		Json denormalise(Json data);

		Json normalise(Json data);
	}
}

interface CratePolicy(T)
{
	inout
	{
		pure
		{
			string mime() nothrow;
			ModelDefinition definition();
			inout(CrateSerializer!T) serializer();

			inout(CrateConfig!T) config();
			string basePath();
		}

		CrateRoutes routes();
	}
}
