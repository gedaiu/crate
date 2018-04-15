module crate.serializer.restapi;

import crate.base, crate.ctfe, crate.generator.openapi;
import crate.error;

import vibe.data.json;
import vibe.data.bson;

import openapi.definitions;

import std.meta, std.string, std.exception, std.array;
import std.algorithm.searching, std.algorithm.iteration;
import std.traits, std.stdio, std.meta, std.conv;
import std.range.interfaces;

class RestApiSerializer : ModelSerializer {
  const { 
    FieldDefinition definition;
    private CrateRestApiSerializer serializer;
  }

  this(const FieldDefinition definition) pure {
    this.definition = definition;
    serializer = new const CrateRestApiSerializer();
  }

  @safe:
    /// Prepare the data to be sent to the client
    Json denormalise(InputRange!Json data) {
      return serializer.denormalise(data, definition);
    }

    //dito
    Json denormalise(Json data) {
      return serializer.denormalise(data, definition);
    }

    /// Get the client data and prepare it for deserialization
    Json normalise(string id, Json data) {
      return serializer.normalise(id, data, definition);
    }
}

class CrateRestApiSerializer : CrateSerializer
{
  @trusted:
  /// Prepare the data to be sent to the client
  Json denormalise(InputRange!Json data, ref const FieldDefinition definition) inout {
    Json result = Json.emptyObject;

    result[plural(definition)] = data.map!(a => extractFields(a, definition)).array;

    return result;
  }

  //dito
  Json denormalise(Json data, ref const FieldDefinition definition) inout {
    Json result = Json.emptyObject;

    result[singular(definition)] = extractFields(data, definition);

    return result;
  }

  private Json extractFields(Json data, ref const FieldDefinition definition) inout {
    Json result = data;

    if(data.type != Json.Type.array && data.type != Json.Type.object) {
      return result;
    }

    if(data.type == Json.Type.array) {
      enforce!CrateValidationException(definition.isArray, "Expected the provided data to match the model definition.");

      return Json((cast(Json[]) data)
        .map!(a => extractFields(a, definition.fields[0]))
        .filter!(a => a.type != Json.Type.undefined)
        .array);
    }

    foreach(field; definition.fields) {
      if(data[field.name].type == Json.Type.undefined && !field.isOptional && field.name != "") {
        throw new CrateValidationException("Missing `" ~ field.name ~ "` value.");
      }

      if(data[field.name].type == Json.Type.undefined && field.isOptional) {
        break;
      }

      string id = field.idOriginalName;

      if(definition.isRelation && field.isId) {
        result = data[field.name];
        break;
      }

      if(id !is null) {
        if(data[field.name].type == Json.Type.array) {
          result[field.name] = Json(data[field.name][0..$].map!(a => a.type == Json.Type.object ? a[id] : a).array);
        } else if(result[field.name].type == Json.Type.object) {
          result[field.name] = data[field.name][id];
        } else {
          result[field.name] = data[field.name];
        }
      } else {
        result[field.name] = extractFields(data[field.name], field);
      }
    }

    return result;
  }

  /// Get the client data and prepare it for deserialization
  Json normalise(string id, Json data, ref const FieldDefinition definition) inout
  {
    auto name = singular(definition);

    enforce!CrateValidationException(name in data,
        "object type expected to be `" ~ name ~ "`");

    foreach(field; definition.fields) {
      if(field.isId) {
        data[name][field.name] = id;
      }
    }

    return data[name];
  }

  private inout pure {
    string singular(const FieldDefinition definition) {
      return definition.singular[0..1].toLower ~ definition.singular[1..$];
    }

    string plural(const FieldDefinition definition) {
      return definition.plural[0..1].toLower ~ definition.plural[1..$];
    }
  }
}

version(unittest) {
  import fluent.asserts;
}

@("Serialize/deserialize a simple struct")
unittest
{
  struct TestModel
  {
    string id;

    string field1;
    int field2;
  }

  auto fields = getFields!TestModel;
  auto serializer = new const CrateRestApiSerializer;

  //test the deserialize method
  auto serialized = `{
    "testModel": {
        "field1": "Ember Hamster",
        "field2": 5
    }
  }`.parseJsonString;

  auto deserialized = serializer.normalise("ID", serialized, fields);
  assert(deserialized["id"] == "ID");
  assert(deserialized["field1"] == "Ember Hamster");
  assert(deserialized["field2"] == 5);

  //test the denormalise method
  auto value = serializer.denormalise(deserialized, fields);
  assert(value["testModel"]["id"] == "ID");
  assert(value["testModel"]["field1"] == "Ember Hamster");
  assert(value["testModel"]["field2"] == 5);
}

@("Serialize an array of structs")
unittest
{
  struct TestModel
  {
    string id;

    string field1;
    int field2;
  }

  auto fields = getFields!TestModel;
  auto serializer = new const CrateRestApiSerializer;

  auto data = [
    TestModel("ID1", "Ember Hamster", 5).serializeToJson,
    TestModel("ID2", "Ember Hamster2", 6).serializeToJson
  ].inputRangeObject;

  //test the serialize method
  auto value = serializer.denormalise(data, fields);

  assert(value["testModels"][0]["id"] == "ID1");
  assert(value["testModels"][0]["field1"] == "Ember Hamster");
  assert(value["testModels"][0]["field2"] == 5);

  assert(value["testModels"][1]["id"] == "ID2");
  assert(value["testModels"][1]["field1"] == "Ember Hamster2");
  assert(value["testModels"][1]["field2"] == 6);
}

@("Check denormalised type")
unittest
{
  @("singular: SingularModel", "plural: PluralModel")
  struct TestModel
  {
    @optional
    {
      string _id;
    }
  }

  auto fields = getFields!TestModel;
  auto serializer = new const CrateRestApiSerializer;
  auto valueSingular = const serializer.denormalise(TestModel().serializeToJson, fields);
  auto valuePlural = const serializer.denormalise([ TestModel().serializeToJson ].inputRangeObject, fields);

  assert("singularModel" in valueSingular);
  assert("pluralModel" in valuePlural);

  assert("_id" in serializer.normalise("", valueSingular, fields));
}

@("Check denormalised object relations")
unittest
{
  struct TestChild
  {
    string _id;
  }

  struct TestModel
  {
    string _id;

    TestChild child;
  }

  auto fields = getFields!TestModel;
  auto serializer = new const CrateRestApiSerializer;

  TestModel test = TestModel("id1", TestChild("id2"));

  auto value = const serializer.denormalise(test.serializeToJson, fields);

  assert(value["testModel"]["child"].type == Json.Type.string);
  assert(value["testModel"]["child"] == "id2");

  value = const serializer.denormalise([test.serializeToJson].inputRangeObject, fields);

  assert(value["testModels"][0]["child"].type == Json.Type.string);
  assert(value["testModels"][0]["child"] == "id2");
}

@("Check denormalised array relations")
unittest
{
  struct TestChild
  {
    string _id;
  }

  struct TestModel
  {
    string _id;
    TestChild[] child;
  }

  auto fields = getFields!TestModel;
  auto serializer = new const CrateRestApiSerializer;

  TestModel test = TestModel("id1", [ TestChild("id2") ]);

  auto value = const serializer.denormalise(test.serializeToJson, fields);

  value["testModel"]["child"][0].type.should.equal(Json.Type.string);
  value["testModel"]["child"][0].to!string.should.equal("id2");
}

@("Check denormalised nested relations")
unittest
{
  struct TestRelation
  {
    string _id;
  }

  struct TestChild
  {
    TestRelation relation;
  }

  struct TestModel
  {
    string _id;
    TestChild child;
    TestChild[] childs = [ TestChild() ];
  }

  auto fields = getFields!TestModel;
  auto serializer = new const CrateRestApiSerializer;

  TestModel test = TestModel("id1");

  test.child.relation._id = "id2";
  test.childs[0].relation._id = "id3";

  auto value = const serializer.denormalise(test.serializeToJson, fields);

  assert(value["testModel"]["child"]["relation"].type == Json.Type.string);
  assert(value["testModel"]["child"]["relation"] == "id2");
  assert(value["testModel"]["childs"].length == 1);
  assert(value["testModel"]["childs"][0]["relation"] == "id3");
}

@("Check denormalised static arrays")
unittest
{
  struct TestModel
  {
    string _id;
    double[2][] child;
  }

  auto fields = getFields!TestModel;

  TestModel test = TestModel("id1");

  test.child = [[1, 2]];

  auto serializer = new const CrateRestApiSerializer;
  auto value = const serializer.denormalise(test.serializeToJson, fields);

  value["testModel"]["child"].length.should.equal(1);
  value["testModel"]["child"][0][0].to!string.should.equal("1");
  value["testModel"]["child"][0][1].to!string.should.equal("2");
}
