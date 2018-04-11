module crate.generator.openapi;

import vibe.http.router;
import crate.base;
import crate.http.router;
import crate.policy.jsonapi;

import openapi.definitions;
import std.stdio, std.string, std.conv, std.traits;
import std.algorithm;
import vibe.data.json;

OperationsType strToType(string value) {
  auto key = value.toLower;

  static foreach(enumValue; EnumMembers!OperationsType) {
    if(enumValue == key) {
      return enumValue;
    }
  }

  throw new Exception("Unknown operation `" ~ value ~ "`");
}

OpenApi toOpenApi(T)(CrateRouter!T router)
{
  OpenApi openApi;
  openApi.components.schemas = errorDefinitions;

  auto routes = router.allRoutes;

  foreach (string key, schema; routes.schemas) {
    openApi.components.schemas[key] = Schema.fromJson(schema);
  }

  foreach (string definedPath, methods; routes.paths) {
    string path = definedPath.toOpenApiPath;
    openApi.paths[path] = Path();

    foreach (method, responses; methods) {
      string strMethod = method.to!string.toLower;
      auto openApiMethod = strToType(strMethod);

      openApi.paths[path].operations[openApiMethod] = Operation();

      foreach (response, pathDefinition; responses) {
        string strResponse = response.to!string;

        openApi.paths[path].operations[strMethod].responses[strResponse] = openapi.definitions.Response();

        if (pathDefinition.schemaName != "") {
          auto refSchema = new Schema;
          refSchema._ref = "#/components/schema/" ~ pathDefinition.schemaName;

          openApi.paths[path][strMethod].responses[strResponse].content["_____SOME JSON"] = MediaType();
          openApi.paths[path][strMethod].responses[strResponse].content["_____SOME JSON"].schema = refSchema;
        }

        if (pathDefinition.operation.isItemOperation)
        {
          openApi.paths[path].operations[strMethod].parameters = [itemId];
          openApi.paths[path][strMethod].responses["404"] = notFoundResponse;
          openApi.paths[path][strMethod].responses["500"] = errorResponse;
        }

        if (pathDefinition.schemaBody != "")
        {
          openApi.paths[path].operations[strMethod].parameters ~= bodyParameter(pathDefinition.schemaBody);
        }
      }
    }
  }

  return openApi;
}

private bool isItemOperation(CrateOperation operation)
{
  return operation == CrateOperation.getItem || operation == CrateOperation.updateItem
    || operation == CrateOperation.replaceItem
    || operation == CrateOperation.deleteItem || operation == CrateOperation.otherItem;
}

private string toOpenApiPath(string path)
{
  return path.replace("/:id", "/{id}");
}

private Path actionPath()
{
  auto actionPath = Path();
  auto operation = Operation();

  operation.tags = ["action"];
  operation.parameters ~= itemId;
  operation.responses = standardResponses;

  actionPath.operations["get"] = operation;

  return actionPath;
}

private Parameter itemId()
{
  auto parameter = Parameter();
  parameter.name = "id";
  parameter.in_ = ParameterIn.path;
  parameter.schema = new Schema;
  parameter.required = true;
  parameter.description = "The item id";
  parameter.schema.type = SchemaType.string;

  return parameter;
}

private Parameter bodyParameter(string name)
{
  auto addParameter = Parameter();
  addParameter.in_ = ParameterIn.body_;
  addParameter.schema = new Schema;
  addParameter.name = name;
  addParameter.required = true;
  addParameter.schema._ref = "#/components/schemas/" ~ name;

  return addParameter;
}

private openapi.definitions.Response[string] standardResponses()
{
  openapi.definitions.Response[string] responses;

  auto okResponse = openapi.definitions.Response();
  okResponse.description = "success";

  auto errorResponse = openapi.definitions.Response();
  errorResponse.description = "server error";
  errorResponse.content["application/json"].schema = new Schema;
  errorResponse.content["application/json"].schema._ref = "#/components/schemas/ErrorList";

  responses["200"] = okResponse;
  responses["404"] = notFoundResponse;
  responses["500"] = errorResponse;

  return responses;
}

private openapi.definitions.Response notFoundResponse()
{
  auto notFoundResponse = openapi.definitions.Response();
  notFoundResponse.description = "not found";
  notFoundResponse.content["application/json"] = MediaType();
  notFoundResponse.content["application/json"].schema = new Schema;
  notFoundResponse.content["application/json"].schema._ref = "#/components/schemas/ErrorList";

  return notFoundResponse;
}

private openapi.definitions.Response errorResponse()
{
  auto errorResponse = openapi.definitions.Response();
  errorResponse.description = "server error";

  errorResponse.content["application/json"] = MediaType();
  errorResponse.content["application/json"].schema = new Schema;
  errorResponse.content["application/json"].schema._ref = "#/components/schemas/ErrorList";

  return errorResponse;
}

private Schema[string] errorDefinitions()
{
  Schema[string] errors;

  Schema error = new Schema();
  Schema errorList = new Schema();

  errorList.type = SchemaType.object;
  errorList.required = ["properties"];
  errorList.properties["properties"] = new Schema;
  errorList.properties["properties"].type = SchemaType.object;
  errorList.properties["properties"].required = ["errors"];
  errorList.properties["properties"].properties["errors"] = new Schema;
  errorList.properties["properties"].properties["errors"].type = SchemaType.array;
  errorList.properties["properties"].properties["errors"].items = new Schema;
  errorList.properties["properties"].properties["errors"].items._ref = "#/components/schemas/Error";

  error.type = SchemaType.object;
  error.properties["status"] = new Schema;
  error.properties["title"] = new Schema;
  error.properties["description"] = new Schema;
  error.properties["status"].type = SchemaType.integer;
  error.properties["status"].format = SchemaFormat.int32;
  error.properties["title"].type = SchemaType.string;
  error.properties["description"].type = SchemaType.string;

  errors["ErrorList"] = errorList;
  errors["Error"] = error;

  return errors;
}

version(unittest)
{
  import fluent.asserts;
  import fluentasserts.vibe.request;
  import vibe.data.serialization;
  import vibe.data.json;
  import crate.collection.memory;

  bool isTestActionCalled;

  struct OtherNested
  {
    string otherName;
  }

  struct Nested
  {
    string name;
    OtherNested other;
  }

  struct TestModel
  {
    @optional
    {
      string _id;
      string other = "";
      string[] tags;
      Nested[] list;
    }

    string name = "";

    void action()
    {
      isTestActionCalled = true;
    }

    string actionResponse()
    {
      isTestActionCalled = true;
      return "ok.";
    }
  }
}

@("Check if all the routes are defined")
unittest
{
  auto router = new URLRouter();
  auto crate = new MemoryCrate!TestModel;

  auto crateRouter = router
                      .crateSetup
                        .add(crate)
                        .enableAction!(MemoryCrate!TestModel, "action")
                        .enableAction!(MemoryCrate!TestModel, "actionResponse");

  auto api = crateRouter.toOpenApi;

  assert(api.paths.length == 4);
  assert(OperationsType.get in api.paths["/testmodels/{id}/action"].operations);
  assert(api.paths["/testmodels/{id}/action"]["get"].parameters.length == 1);
  assert(api.paths["/testmodels/{id}/action"]["get"].parameters[0].name == "id");

  assert("ErrorList" in api.components.schemas);
  assert("Error" in api.components.schemas);
  assert("TestModelList" in api.components.schemas);
  assert("TestModelResponse" in api.components.schemas);
  assert("TestModelRequest" in api.components.schemas);
  assert(OperationsType.get in api.paths["/testmodels/{id}/actionResponse"].operations);
}

@("Check if the array property has the right definition")
unittest
{
  auto router = new URLRouter();
  auto crate = new MemoryCrate!TestModel;

  auto crateRouter = router.crateSetup!CrateJsonApiPolicy.add(crate);

  auto api = crateRouter.toOpenApi.serializeToJson;

  api["components"]["schemas"].byKeyValue.map!"a.key".should.contain("TestModelAttributes");

  auto testModelAttributesDefinition = api["components"]["schemas"]["TestModelAttributes"];

  Json expected = `{
    "required": [
      "name"
    ],
    "type": "object",
    "properties": {
      "tags": {
        "type": "array",
        "items": {
          "type": "string"
        }
      },
      "name": {
        "type": "string"
      },
      "list": {
        "type": "array",
        "items": {
          "$ref": "#/components/schemas/NestedModel"
        }
      },
      "other": {
        "type": "string"
      }
    }
  }`.parseJsonString;

  testModelAttributesDefinition.should.equal(expected);
}

@("Check if the nested property has the right definition")
unittest
{
  auto router = new URLRouter();
  auto crate = new MemoryCrate!TestModel;

  auto crateRouter = router.crateSetup!CrateJsonApiPolicy.add(crate);

  auto api = crateRouter.toOpenApi.serializeToJson;

  api["components"]["schemas"].byKeyValue.map!"a.key".should.contain("NestedModel");

  auto nestedModelDefinition = api["components"]["schemas"]["NestedModel"];
  nestedModelDefinition["properties"]["name"]["type"].to!string.should.equal("string");
  nestedModelDefinition["properties"]["other"]["$ref"].to!string.should.equal("#/components/schemas/OtherNestedModel");
}

string asOpenApiType(string dType)
{
  switch (dType)
  {
  case "int":
    return "integer";

  case "long":
    return "integer";

  case "float":
    return "number";

  case "double":
    return "number";

  case "string":
    return "string";

  case "bool":
    return "boolean";

  case "SysTime":
    return "string";

  case "DateTime":
    return "string";

  default:
    return "object";
  }
}

string asOpenApiFormat(string dType)
{
  switch (dType)
  {
  case "int":
    return "int32";

  case "long":
    return "int64";

  case "float":
    return "float";

  case "double":
    return "double";

  case "string":
    return "";

  case "bool":
    return "";

  case "SysTime":
  case "DateTime":
    return "date-time";

  case "Date":
    return "date";

  default:
    return "";
  }
}
