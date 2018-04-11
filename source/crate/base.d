module crate.base;

import vibe.data.json, vibe.http.common;

import std.string, std.traits, std.conv;
import std.algorithm, std.range, std.string;
import std.range.interfaces;
import vibe.http.server;

import crate.ctfe;

import openapi.definitions;

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


interface ICrateFilter
{
  ICrateSelector apply(HTTPServerRequest, ICrateSelector);
}

interface ICrateSelector
{
  ICrateSelector where(string field, string value);
  ICrateSelector whereArrayContains(string field, string value);
  ICrateSelector whereArrayFieldContains(string arrayField, string field, string value);
  ICrateSelector limit(size_t nr);

  InputRange!Json exec();
}

class CrateRange : ICrateSelector
{
  private {
    InputRange!Json data;
  }

  this(Json[] data) {
    this.data = inputRangeObject(data);
  }

  this(T)(T data) {
    this.data = data.inputRangeObject;
  }

  override {
    ICrateSelector where(string field, string value) {
      data = data.filter!(a => a[field].to!string == value).inputRangeObject;
      return this;
    }

    ICrateSelector whereArrayContains(string field, string value) {
      data = data.filter!(a => (cast(Json[])a[field]).canFind(Json(value))).inputRangeObject;
      return this;
    }

    ICrateSelector whereArrayFieldContains(string arrayField, string field, string value) {
      data = data.filter!(a => (cast(Json[])a[arrayField])
                .map!(a => a[field])
                .canFind(Json(value))).inputRangeObject;
      return this;
    }

    ICrateSelector limit(size_t nr) {
      data = data.take(nr).inputRangeObject;
      return this;
    }

    InputRange!Json exec() {
      return data;
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

  ICrateSelector getList(string[string] parameters);
  ICrateSelector getItem(string id);

  Json addItem(Json item);
  void updateItem(Json item);
  void deleteItem(string id);
}

interface CrateSerializer
{
  inout
  {
    /// Prepare the data to be sent to the client
    Json denormalise(InputRange!Json data, ref const FieldDefinition definition);
    /// ditto
    Json denormalise(Json data, ref const FieldDefinition definition);

    /// Get the client data and prepare it for deserialization
    Json normalise(string id, Json data, ref const FieldDefinition definition);
  }
}

interface ModelSerializer
{
  @safe
  {
    /// Prepare the data to be sent to the client
    Json denormalise(InputRange!Json data);
    /// ditto
    Json denormalise(Json data);

    /// Get the client data and prepare it for deserialization
    Json normalise(string id, Json data);
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
