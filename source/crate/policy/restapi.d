module crate.policy.restapi;

import crate.base;
import crate.serializer.restapi;
import crate.routing.restapi;
import crate.generator.openapi;
import crate.ctfe;

import vibe.data.json;
import vibe.http.common;

import openapi.definitions;

import std.string, std.stdio;

struct RestApi {
  static immutable {
    string name = "Rest API";
    string mime = "application/json";
  }

  alias Serializer = RestApiSerializer;
  alias Routing = RestApiRouting;

  static pure:
    private CrateRule templateRule(FieldDefinition definition) {
      auto serializer = new RestApiSerializer(definition);
      CrateRule rule;

      rule.request.serializer = serializer;

      rule.response.mime = "application/json";
      rule.response.serializer = serializer;

      rule.schemas[definition.type ~ "Attributes"] = definition.toSchema(false);

      return rule;
    }

    CrateRule replace(FieldDefinition definition) {
      auto routing = new Routing(definition);
      CrateRule rule = templateRule(definition);

      rule.request.path = routing.put;
      rule.request.method = HTTPMethod.PUT;
      rule.response.statusCode = 200;

      return rule;
    }

    CrateRule create(FieldDefinition definition) {
      auto routing = new Routing(definition);
      CrateRule rule = templateRule(definition);

      rule.request.path = routing.post;
      rule.request.method = HTTPMethod.POST;
      rule.response.statusCode = 201;

      return rule;
    }

    CrateRule delete_(FieldDefinition definition) {
      auto routing = new Routing(definition);
      CrateRule rule = templateRule(definition);

      rule.request.path = routing.delete_;
      rule.request.method = HTTPMethod.DELETE;
      rule.response.statusCode = 204;

      return rule;
    }

    CrateRule getItem(FieldDefinition definition) {
      auto routing = new Routing(definition);
      CrateRule rule = templateRule(definition);

      rule.request.path = routing.get;
      rule.request.method = HTTPMethod.GET;
      rule.response.statusCode = 200;

      return rule;
    }

    CrateRule patch(FieldDefinition definition) {
      auto routing = new Routing(definition);
      CrateRule rule = templateRule(definition);

      rule.request.method = HTTPMethod.PATCH;
      rule.request.path = routing.get;
      rule.response.statusCode = 200;

      return rule;
    }

    CrateRule getList(FieldDefinition definition) {
      auto routing = new Routing(definition);
      CrateRule rule = templateRule(definition);

      rule.request.path = routing.getList;
      rule.request.method = HTTPMethod.GET;
      rule.response.statusCode = 200;

      rule.schemas[definition.type ~ "Request"] = new Schema;
      rule.schemas[definition.type ~ "Response"] = new Schema;
      rule.schemas[definition.type ~ "List"] = new Schema;

      return rule;
    }

    CrateRule getResource(string path)(FieldDefinition definition) {
      auto routing = new Routing(definition);
      CrateRule rule = templateRule(definition);

      rule.request.path = routing.get ~ path;
      rule.request.method = HTTPMethod.GET;
      rule.response.statusCode = 200;

      return rule;
    }

    CrateRule setResource(string path)(FieldDefinition definition) {
      auto routing = new Routing(definition);
      CrateRule rule = templateRule(definition);

      rule.request.path = routing.get ~ path;
      rule.request.method = HTTPMethod.POST;
      rule.response.statusCode = 201;

      return rule;
    }

    CrateRule action(MethodReturnType, ParameterType, string actionName)(FieldDefinition definition) {
      auto routing = new RestApiRouting(definition);
      CrateRule rule;

      rule.request.path = routing.get ~ "/" ~ actionName;

      static if(is(ParameterType == void)) {
        rule.request.method = HTTPMethod.GET;
      } else {
        rule.request.method = HTTPMethod.POST;
      }

      rule.response.statusCode = 200;

      return rule;
    }
}

class CrateRestApiPolicy : CratePolicy
{
  private
  {
    CrateRestApiSerializer _serializer  = new inout CrateRestApiSerializer;
  }

  string name() inout pure nothrow
  {
    return "Rest API";
  }

  inout(CrateSerializer) serializer() inout pure nothrow
  {
    return _serializer;
  }

  string mime() inout pure nothrow
  {
    return "application/json";
  }
}

CrateRoutes defineRoutes(T)(const CrateRestApiPolicy, const CrateConfig!T config)
{
  CrateRoutes definedRoutes;

  definedRoutes.schemas = schemas!T;
  definedRoutes.paths = config.paths!T;

  return definedRoutes;
}

string basePath(T)(const CrateConfig!T config) pure
{
  return "/" ~ config.plural.toLower;
}

ModelDefinition definition(T)() pure
{
  ModelDefinition model;

  enum FieldDefinition[] fields = getFields!T.fields;

  foreach (index, field; fields)
  {
    model.fields[field.name] = field;

    if (field.isId)
    {
      model.idField = field.name;
    }
  }

  return model;
}

private
{
  PathDefinition[uint][HTTPMethod][string] paths(T)(const CrateConfig!T config)
  {
    PathDefinition[uint][HTTPMethod][string] selectedPaths;

    if (config.getList)
    {
      selectedPaths[config.basePath][HTTPMethod.GET][200] = PathDefinition(T.stringof ~ "List",
          "", CrateOperation.getList);
    }

    if (config.addItem)
    {
      selectedPaths[config.basePath][HTTPMethod.POST][200] = PathDefinition(T.stringof ~ "Response",
          T.stringof ~ "Request", CrateOperation.addItem);
    }

    if (config.getItem)
    {
      selectedPaths[config.basePath ~ "/:id"][HTTPMethod.GET][200] = PathDefinition(T.stringof ~ "Response",
          "", CrateOperation.getItem);
    }

    if (config.replaceItem)
    {
      selectedPaths[config.basePath ~ "/:id"][HTTPMethod.PATCH][200] = PathDefinition(T.stringof ~ "Response",
          T.stringof ~ "Request", CrateOperation.replaceItem);
    }

    if (config.deleteItem)
    {
      selectedPaths[config.basePath ~ "/:id"][HTTPMethod.DELETE][201] = PathDefinition("",
          "", CrateOperation.deleteItem);
    }

    return selectedPaths;
  }

  Json[string] schemas(T)()
  {
    Json[string] schemaList;

    schemaList[T.stringof ~ "Response"] = schemaResponse!T;
    schemaList[T.stringof ~ "List"] = schemaResponseList!T;
    schemaList[T.stringof ~ "Request"] = schemaRequest!T;
    schemaList[T.stringof] = schemaModel!T;
    schemaList["StringResponse"] = schemaString;

    addRelations!T(schemaList);

    return schemaList;
  }

  Json schemaString()
  {
    Json data = Json.emptyObject;
    data["type"] = "string";
    return data;
  }

  void addRelations(T)(ref Json[string] data)
  {
    void describeRelations(FieldDefinition[] fields)()
    {
      static if (fields.length == 1)
      {
        static if (fields[0].type == "BsonObjectID" || fields[0].type == "ObjectId")
        {
          data[fields[0].type] = Json.emptyObject;
          data[fields[0].type]["type"] = "string";
        }
        else static if (!fields[0].isBasicType && fields[0].originalName != "")
        {
          alias Type = FieldType!(__traits(getMember, T, fields[0].originalName));

          data[fields[0].type] = Json.emptyObject;
          describe!Type(data[fields[0].type]);
        }
      }
      else static if (fields.length > 1)
      {
        describeRelations!([fields[0]])();
        describeRelations!(fields[1 .. $])();
      }
    }

    enum FieldDefinition[] fields = getFields!T.fields;
    describeRelations!(fields);
  }

  Json schemaResponse(T)()
  {
    enum singular = Singular!T[0..1].toLower ~ Singular!T[1..$];

    auto data = Json.emptyObject;
    data["type"] = "object";
    data["properties"] = Json.emptyObject;
    data["properties"][singular] = Json.emptyObject;
    data["properties"][singular]["$ref"] = "#/components/schemas/" ~ T.stringof;

    return data;
  }

  Json schemaResponseList(T)()
  {
    enum plural = Plural!T[0..1].toLower ~ Plural!T[1..$];

    auto data = Json.emptyObject;
    data["type"] = "object";
    data["properties"] = Json.emptyObject;
    data["properties"][plural] = Json.emptyObject;
    data["properties"][plural]["type"] = "array";
    data["properties"][plural]["items"] = Json.emptyObject;
    data["properties"][plural]["items"]["$ref"] = "#/components/schemas/" ~ T.stringof;

    return data;
  }

  void describe(T, bool includeId = true)(ref Json data)
  {
    data["type"] = "object";
    data["properties"] = Json.emptyObject;

    void addField(FieldDefinition field)()
    {
      data["properties"][field.name] = Json.emptyObject;
      enum type = field.type.asOpenApiType;

      static if (field.isRelation)
      {
        data["properties"][field.name]["type"] = "string";
        data["properties"][field.name]["description"] = "The id of an existing `"
          ~ field.type ~ "`";
      }
      else static if (type == "object")
      {
        enum refObj = "#/components/schemas/" ~ field.type;

        static if (field.isArray)
        {
          data["properties"][field.name]["type"] = "array";
          data["properties"][field.name]["items"] = Json.emptyObject;
          data["properties"][field.name]["items"]["$ref"] = refObj;
        }
        else
        {
          data["properties"][field.name]["$ref"] = refObj;
        }
      }
      else
      {
        static if (field.isArray)
        {
          data["properties"][field.name]["type"] = "array";
          data["properties"][field.name]["items"] = Json.emptyObject;
          data["properties"][field.name]["items"]["type"] = type;
        }
        else
        {
          data["properties"][field.name]["type"] = type;
        }
      }

      static if (!field.isOptional)
      {
        if (data["required"].type == Json.Type.undefined)
        {
          data["required"] = Json.emptyArray;
        }

        data["required"] ~= field.name;
      }
    }

    void describeFields(FieldDefinition[] fields)()
    {
      static if (fields.length == 1)
      {
        static if (fields[0].isId && !includeId)
        {
          return;
        }
        else
        {
          addField!(fields[0]);
        }
      }
      else static if (fields.length > 1)
      {
        describeFields!([fields[0]])();
        describeFields!(fields[1 .. $])();
      }
    }

    enum FieldDefinition[] fields = Describe!T.fields;
    describeFields!(fields);
  }

  Json schemaRequest(T)()
  {
    enum singular = Singular!T[0..1].toLower ~ Singular!T[1..$];

    auto data = Json.emptyObject;
    data["type"] = "object";
    data["properties"] = Json.emptyObject;
    data["properties"][singular] = Json.emptyObject;

    describe!(T, false)(data["properties"][singular]);

    return data;
  }

  Json schemaModel(T)()
  {
    auto data = Json.emptyObject;

    describe!T(data);

    return data;
  }
}






@("Open api schema")
unittest
{
  struct TestModel
  {
    string id;

    string field1;
    int field2;
  }

  auto schema = schemas!TestModel.serializeToJson;


  assert(schema["TestModelResponse"]["type"] == "object");
  assert(
      schema["TestModelResponse"]["properties"]["testModel"]["$ref"] == "#/components/schemas/TestModel");

  assert(schema["TestModelList"]["type"] == "object");

  assert(schema["TestModelList"]["properties"]["testModels"]["type"] == "array");

  assert(
      schema["TestModelList"]["properties"]["testModels"]["items"]["$ref"] == "#/components/schemas/TestModel");

  assert(schema["TestModelRequest"]["type"] == "object");

  assert(schema["TestModelRequest"]["properties"]["testModel"]["type"] == "object");

  assert(
      schema["TestModelRequest"]["properties"]["testModel"]["properties"]["id"].type
      == Json.Type.undefined);

  assert(
      schema["TestModelRequest"]["properties"]["testModel"]["properties"]["field1"]["type"] == "string");

  assert(
      schema["TestModelRequest"]["properties"]["testModel"]["properties"]["field2"]["type"] == "integer");

  assert(schema["TestModel"]["type"] == "object");

  assert(schema["TestModel"]["properties"]["id"]["type"] == "string");

  assert(schema["TestModel"]["properties"]["field1"]["type"] == "string");

  assert(schema["TestModel"]["properties"]["field2"]["type"] == "integer");
}

@("Open api schema with detailed objects")
unittest
{
  struct TestModel
  {
    string name;
  }

  struct ComposedModel
  {
    @optional
    {
      string _id;
    }

    TestModel child;
  }

  auto schema = schemas!ComposedModel.serializeToJson;

  assert(schema["ComposedModel"]["type"] == "object");
  assert(schema["ComposedModel"]["properties"]["child"]["$ref"] == "#/components/schemas/TestModel");

  assert(schema["TestModel"]["type"] == "object");
  assert(schema["TestModel"]["properties"]["name"]["type"] == "string");
}

@("Open api schema with relations")
unittest
{
  struct TestModel
  {
    string id;
    string name;
  }

  struct ComposedModel
  {
    @optional
    {
      string _id;
    }

    TestModel child;
  }

  auto schema = schemas!ComposedModel;

  assert(schema["ComposedModel"]["type"] == "object");
  assert(schema["ComposedModel"]["properties"]["child"]["type"] == "string");
}
