module crate.base;

import vibe.data.json, vibe.http.common;

import std.string, std.traits, std.conv;

import swaggerize.definitions;

enum CrateOperation {
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
	enum string singular = T.stringof[0..1].toLower ~ T.stringof[1..$];
	enum string plural = T.stringof[0..1].toLower ~ T.stringof[1..$] ~ "s";

	bool getList = true;
	bool getItem = true;
	bool addItem = true;
	bool deleteItem = true;
	bool replaceItem = true;
	bool updateItem = true;
}

struct PathDefinition {
	string schemaName;
	string schemaBody;
	CrateOperation operation;
}

struct CrateRoutes {
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
	void updateItem(T item);
	void deleteItem(string id);
}

interface CrateSerializer(T)
{
	Json serialize(T item, Json replace = Json.emptyObject);
	Json serialize(T[] items);

	T deserialize(Json data);

	string mime();
	ModelDefinition definition();

	CrateConfig!T config();
	string basePath();
	CrateRoutes routes();
}
