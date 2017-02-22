module crate.collection.idcreator;

import crate.base;
import crate.ctfe;

import std.algorithm, std.array;

import vibe.data.json;
import vibe.data.bson;

version(unittest) {
  import std.stdio;
}

struct IdCreator {
  Json data;
  FieldDefinition definition;

  Json toJson() {
    Json newData = data;

    if(newData.type != Json.Type.object) {
      return newData;
    }

    foreach(field; definition.fields) {
      if((field.name !in data || data[field.name].to!string.length != 24) && field.originalType == "BsonObjectID") {
        newData[field.name] = BsonObjectID.generate.toString;
      } else if(field.name !in data && field.isId) {
        newData[field.name] = "";
      } else if(data[field.name].type == Json.Type.object) {
        newData[field.name] = IdCreator(data[field.name], field).toJson;
      } else if(data[field.name].type == Json.Type.array) {
        newData[field.name] = Json(data[field.name].opCast!(Json[]).map!(a => IdCreator(a, field.fields[0]).toJson).array);
      }
    }

    return newData;
  }
}

struct ItemIdCreator {
  Json data;
  FieldDefinition definition;

  Json toJson() {
    Json newData = data;

    if(newData.type != Json.Type.object) {
      return newData;
    }

    foreach(field; definition.fields) {
      if((field.name !in data || data[field.name].to!string.length != 24) && field.originalType == "BsonObjectID") {
        newData[field.name] = BsonObjectID.generate.toString;
      } else if(field.name !in data && field.isId) {
        newData[field.name] = "";
      }
    }

    return newData;
  }
}

@("It should remove the _id field")
unittest {
  struct Relation {
    string id;
    BsonObjectID _id;
    string name;
  }

  struct Test {
    BsonObjectID _id;
    string name;

    Relation relation;
    Relation[] relations;
  }

  Json test = `{
    "name": "",
    "relation": {
      "name": ""
    },
    "relations": [{
      "name": ""
    }]
  }`.parseJsonString;

  Json result = IdCreator(test, getFields!Test).toJson;

  assert("_id" in result);
  assert("name" in result);
  assert("relation" in result);
  assert("relations" in result);

  assert("id" in result["relation"]);
  assert("_id" in result["relation"]);
  assert("name" in result["relation"]);

  assert("id" in result["relations"][0]);
  assert("_id" in result["relations"][0]);
  assert("name" in result["relations"][0]);
}
