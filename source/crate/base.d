module crate.base;

import vibe.data.json, vibe.http.common;

import std.string, std.traits, std.conv;
import std.algorithm, std.range, std.string;

import crate.ctfe;

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

abstract class ICrateSelector
{
	ICrateSelector where(string field, string value);
	ICrateSelector whereArrayContains(string field, string value);
	ICrateSelector whereArrayFieldContains(string arrayField, string field, string value);
	ICrateSelector limit(ulong nr);

	Json[] exec();
}

class CrateRange : ICrateSelector
{
	private {
		InputRange!Json data;
	}

	this(Json[] data) {
		this.data = inputRangeObject(data);
	}

	override {
		ICrateSelector where(string field, string value) {
			data = inputRangeObject(data.filter!(a => a[field].to!string == value));
			return this;
		}

		ICrateSelector whereArrayContains(string field, string value) {
			data = inputRangeObject(data.filter!(a => (cast(Json[])a[field]).canFind(Json(value))));
			return this;
		}

		ICrateSelector whereArrayFieldContains(string arrayField, string field, string value) {
			data = inputRangeObject(data.filter!(a => (cast(Json[])a[arrayField])
								.map!(a => a[field])
								.canFind(Json(value))));
			return this;
		}

		ICrateSelector limit(ulong nr) {
			data = inputRangeObject(data.take(nr));
			return this;
		}

		Json[] exec() {
			return data.array;
		}
	}
}

struct CrateConfig(T)
{
	bool getList = true;
	bool getItem = true;
	bool addItem = true;
	bool deleteItem = true;
	bool replaceItem = true;
	bool updateItem = true;

	static if(is(T == void)) {
		string singular;
		string plural;
	} else {
		string singular = Singular!T;
		string plural = Plural!T;
	}
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
	CrateConfig!Type config();

	ICrateSelector get();

	Json[] getList(string[string] parameters);

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
