module crate.base;

import vibe.data.json, vibe.http.common;

import std.string, std.traits, std.conv;
import std.algorithm, std.range;

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
	string originalType;
	bool isBasicType;
	bool isRelation;
	bool isId;
	bool isOptional;
	bool isArray;

	FieldDefinition[] fields;
	string singular;
	string plural;
}

FieldDefinition idField(FieldDefinition field) pure
{
	return field.fields.filter!(a => a.isId).takeExactly(1).front;
}

string idOriginalName(const FieldDefinition definition) pure {
	foreach(field; definition.fields) {
		if(field.isId) {
			return field.originalName;
		}
	}

	return null;
}

struct ModelDefinition
{
	string idField;
	FieldDefinition[string] fields;
}

interface Crate(Type)
{
	CrateConfig config();

	Json[] get(string field, string value, ulong limit);

	Json[] getList();

	Json addItem(Json item);
	Json getItem(string id);
	void updateItem(Json item);
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
