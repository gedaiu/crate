module crate.collection.idremover;

import crate.base;
import crate.ctfe;

import std.algorithm, std.array;

import vibe.data.json;

version(unittest) {
  import vibe.data.bson;
  import std.stdio;
}

struct IdRemover {
  Json data;
  FieldDefinition definition;

  Json toJson() {
    Json newData = Json.emptyObject;

    foreach(field; definition.fields) {
      if(!field.isId && field.name in data) {
        if(data[field.name].type == Json.Type.object) {
          newData[field.name] = IdRemover(data[field.name], field).toJson;
        } else if(data[field.name].type == Json.Type.array) {
          newData[field.name] = Json(data[field.name].opCast!(Json[]).map!(a => IdRemover(a, field).toJson ).array);
        } else {
          newData[field.name] = data[field.name];
        }
      }
    }

    return newData;
  }
}

@("It should remove the _id field")
unittest {
  struct Relation {
    BsonObjectID _id;
    string name;
  }

  struct Test {
    BsonObjectID _id;
    string name;

    Relation relation;
    Relation[] relations;
  }

  Test test = Test();

  test.relations ~= Relation();

  Json result = IdRemover(test.serializeToJson, getFields!Test).toJson();

  assert("_id" !in result);
  assert("name" in result);
  assert("relation" in result);
  assert("relations" in result);

  assert("_id" !in result["relation"]);
  assert("name" in result["relation"]);

  assert("_id" !in result["relations"][0]);
  assert("name" in result["relations"][0]);
}
