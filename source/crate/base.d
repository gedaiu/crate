module crate.base;

import vibe.data.json, vibe.http.common;

import std.string, std.traits, std.conv, std.typecons;
import std.algorithm, std.range, std.string;
import std.range.interfaces;
import vibe.http.server;

import crate.ctfe;
import vibe.data.bson;

import openapi.definitions;

version(unittest) import fluent.asserts;

struct ObjectId {
  Bson bsonObjectID;
  alias bsonObjectID this;

  static ObjectId generate() {
    return ObjectId(Bson(BsonObjectID.generate));
  }

  static ObjectId fromString(string value) @safe {
    return ObjectId(Bson(BsonObjectID.fromString(value)));
  }

  string toString() @safe const {
    if(bsonObjectID.type != Bson.Type.objectID) {
      return "";
    }

    return bsonObjectID.to!string[1..$-1];
  }

  Bson toBson() const @safe {
    if(bsonObjectID.type != Bson.Type.objectID) {
      return Bson.fromJson(Json.undefined);
    }

    return bsonObjectID;
  }

  static ObjectId fromBson(Bson src) @safe {
    return ObjectId(src);
  }


  Json toJson() const @safe {
    if(bsonObjectID.type != Bson.Type.objectID) {
      return Json.undefined;
    }

    return Json(toString);
  }

  static ObjectId fromJson(Json src) @safe {
    if(src.type != Json.Type.string) {
      return ObjectId(Bson.fromJson(Json.undefined));
    }

    return ObjectId.fromString(src.get!string);
  }
}

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
  @safe:
    ICrateSelector where(string field, string value);
    ICrateSelector whereArrayContains(string field, string value);
    ICrateSelector whereArrayFieldContains(string arrayField, string field, string value);
    ICrateSelector limit(size_t nr);

    InputRange!Json exec();
}

struct CrateResponse {
  string mime;
  uint statusCode;
  ModelSerializer serializer;
  Schema schema;
}

struct CrateRequest {
  HTTPMethod method;
  string path;
  ModelSerializer serializer;
  Schema schema;
}

struct CrateRule {
  CrateRequest request;
  CrateResponse response;
  Schema[string] schemas;
}

/// Takes a nested Json object and moves the values to a Json assoc array where the key 
/// is the path from the original object to that value
Json[string] flatten(Json object) @trusted {
  Json[string] elements;

  auto root = tuple("", object);
  Tuple!(string, Json)[] queue = [ root ];

  while(queue.length > 0) {
    auto element = queue[0];

    if(element[0] != "") {
      if(element[1].type != Json.Type.object && element[1].type != Json.Type.array) {
        elements[element[0]] = element[1];
      }

      if(element[1].type == Json.Type.object && element[1].length == 0) {
        elements[element[0]] = element[1];
      }

      if(element[1].type == Json.Type.array && element[1].length == 0) {
        elements[element[0]] = element[1];
      }
    }

    if(element[1].type == Json.Type.object) {
      foreach(string key, value; element[1].byKeyValue) {
        string nextKey = key;

        if(element[0] != "") {
          nextKey = element[0] ~ "." ~ nextKey;
        }

        queue ~= tuple(nextKey, value);
      }
    }

    if(element[1].type == Json.Type.array) {
      size_t index;

      foreach(value; element[1].byValue) {
        string nextKey = element[0] ~ "[" ~ index.to!string ~ "]";

        queue ~= tuple(nextKey, value);
        index++;
      }
    }

    queue = queue[1..$];
  }

  return elements;
}

/// Get a flatten object
unittest {
  auto obj = Json.emptyObject;
  obj["key1"] = 1;
  obj["key2"] = 2;
  obj["key3"] = Json.emptyObject;
  obj["key3"]["item1"] = "3";
  obj["key3"]["item2"] = Json.emptyObject;
  obj["key3"]["item2"]["item4"] = Json.emptyObject;
  obj["key3"]["item2"]["item5"] = Json.emptyObject;
  obj["key3"]["item2"]["item5"]["item6"] = Json.emptyObject;
  
  auto result = obj.flatten;
  result.byKeyValue.map!(a => a.key).should.containOnly(["key1", "key2", "key3.item1", "key3.item2.item4", "key3.item2.item5.item6"]);
  result["key1"].should.equal(1);
  result["key2"].should.equal(2);
  result["key3.item1"].should.equal("3");
  result["key3.item2.item4"].should.equal(Json.emptyObject);
  result["key3.item2.item5.item6"].should.equal(Json.emptyObject);
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
      data = data
        .map!(a => tuple(a, a.flatten))
        .filter!(a => a[1][field].to!string == value)
        .map!(a => a[0])
          .inputRangeObject;

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

    InputRange!Json exec() @trusted {
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
  Schema[string] schemas;
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
  @safe:
    CrateConfig!Type config();

    ICrateSelector get();

    ICrateSelector getList();
    ICrateSelector getItem(string id);

    Json addItem(Json item);
    Json updateItem(Json item);
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
    /// Get the model definitin assigned to the serializer
    FieldDefinition definition();

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
