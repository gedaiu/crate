module crate.base;

import vibe.data.json, vibe.http.common;

import std.string, std.traits, std.conv, std.typecons;
import std.algorithm, std.range, std.string;
import std.range.interfaces;
import vibe.http.server;
import vibe.http.router;

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
    import std.stdio;
    static immutable fill = "000000000000000000000000";

    if(value.length > 2 && value[0] == '"' && value[$-1..$] == `"`) {
      value = value[1..$-1];
    }

    if(value.length < 24) {
      value = fill[0..$-value.length] ~ value;
    }

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

    string strId = src.get!string;

    return ObjectId.fromString(strId);
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

/// A Crate filter is a specialized middelware which filters the database data
/// based on a request parameters
interface ICrateFilter {
  /// Filter the data
  ICrateSelector apply(HTTPServerRequest, ICrateSelector);
}

/// A crate is a specialized interface to perform DB selectors.
/// All the selectors must implement theese selectors.
/// Performing multiple operations over the same selectors are grouped
/// with an `and` logic operator
interface ICrateSelector {
  @safe:
    /// March an item if exactly one field value
    ICrateSelector where(string field, string value);
    /// ditto
    ICrateSelector where(string field, bool value);

    /// Match an item if a filed value contains at least one value from the values list
    ICrateSelector whereAny(string field, string[] values);
    /// ditto
    ICrateSelector whereAny(string field, ObjectId[] ids);

    /// Match an item if the array field contains at least one value from the values list
    ICrateSelector whereArrayAny(string arrayField, string[] values);
    /// ditto
    ICrateSelector whereArrayAny(string arrayField, ObjectId[] ids);

    /// Match an item if the array field contains the `value` element
    ICrateSelector whereArrayContains(string arrayField, string value);

    /// Match an item if an array field contains an object that has the field equals with the value
    ICrateSelector whereArrayFieldContains(string arrayField, string field, string value);

    /// Match an item using a substring
    ICrateSelector like(string field, string value);

    /// Limit the number of results
    ICrateSelector limit(size_t nr);

    /// Execute the selector and return a range of JSONs
    InputRange!Json exec();
}

/// Struct used to define response rules
struct CrateResponse {
  /// Response mime
  string mime;

  /// Response sttatus code
  uint statusCode;

  ///
  string[string] headers;
  
  /// Serializer used to convert the json
  ModelSerializer serializer;

  /// How the data will look after serialization
  Schema schema;
}

/// Struct used to define request rules
struct CrateRequest {
  /// The expected method
  HTTPMethod method;

  ///
  string path;

  /// Serializer used to normalize the json
  ModelSerializer serializer;

  /// How the sent data should look
  Schema schema;
}

/// Crate rules definitions
struct CrateRule {
  CrateRequest request;
  CrateResponse response;
  Schema[string] schemas;
}

/// Apply a rule to a URLRouter
URLRouter addRule(T)(URLRouter router, CrateRule rule, T handler) {
  import crate.generator.openapi : addApi;
  import crate.http.cors : Cors;

  router.addApi(rule);
  auto cors = Cors(router, rule.request.path);

  return router.match(rule.request.method, rule.request.path, cors.add(rule.request.method, handler));
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

/// Convert a Json range to a ICrateSelector
class CrateRange : ICrateSelector
{
  private {
    InputRange!Json data;
  }

  ///
  this(Json[] data) {
    this.data = inputRangeObject(data);
  }

  ///
  this(T)(T data) {
    this.data = data.inputRangeObject;
  }

  override @trusted {

    /// March an item if exactly one field value
    ICrateSelector where(string field, string value) @trusted {
      data = data
        .map!(a => tuple(a, a.flatten))
        .filter!(a => field in a[1])
        .filter!(a => a[1][field].to!string == value)
        .map!(a => a[0])
          .inputRangeObject;

      return this;
    }

    /// ditto
    ICrateSelector where(string field, bool value) {
      data = data
        .map!(a => tuple(a, a.flatten))
        .filter!(a => field in a[1])
        .filter!(a => a[1][field].to!bool == value)
        .map!(a => a[0])
          .inputRangeObject;

      return this;
    }
    
    /// Match an item if a filed value contains at least one value from the values list
    ICrateSelector whereAny(string field, string[] values) @safe {
      data = data
        .map!(a => tuple(a, a.flatten))
        .filter!(a => field in a[1])
        .filter!(a => values.canFind(a[1][field].to!string))
        .map!(a => a[0])
          .inputRangeObject;

      return this;
    }
    //ditto
    ICrateSelector whereAny(string field, ObjectId[] ids) {
      return whereAny(field, ids.map!(a => a.toString).array);
    }

    /// Match an item if the array field contains at least one value from the values list
    ICrateSelector whereArrayAny(string arrayField, string[] values) {
      return whereAny(arrayField, values);
    }

    /// ditto
    ICrateSelector whereArrayAny(string arrayField, ObjectId[] ids) {
      return whereAny(arrayField, ids);
    }

    /// Match an item if the array field contains the `value` element
    ICrateSelector whereArrayContains(string field, string value) {
      data = data.filter!(a => (cast(Json[])a[field]).canFind(Json(value))).inputRangeObject;
      return this;
    }

    /// Match an item if an array field contains an object that has the field equals with the value
    ICrateSelector whereArrayFieldContains(string arrayField, string field, string value) {
      data = data
              .filter!(a => (cast(Json[])a[arrayField])
                .map!(a => a[field])
                .canFind(Json(value)))
                .inputRangeObject;

      return this;
    }

    /// Match an item using a substring
    ICrateSelector like(string field, string value) {
      data = data
        .map!(a => tuple(a, a.flatten))
        .filter!(a => field in a[1])
        .filter!(a => a[1][field].to!string.canFind(value))
        .map!(a => a[0])
          .inputRangeObject;

      return this;
    }

    /// Limit the number of results
    ICrateSelector limit(size_t nr) {
      data = data.take(nr).inputRangeObject;
      return this;
    }

    /// Execute the selector and return a range of JSONs
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

alias CrateGetter = ICrateSelector delegate(string) @safe;

CrateGetter[string] crateGetters;

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
