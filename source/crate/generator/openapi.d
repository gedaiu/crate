module crate.generator.openapi;

import vibe.http.router;
import crate.base;
import crate.http.router;
import crate.policy.jsonapi;

import swaggerize.definitions;
import std.stdio, std.string, std.conv;
import vibe.data.json;

Swagger toOpenApi(T)(CrateRouter!T router)
{
	Swagger openApi;
	openApi.host = "localhost";
	openApi.schemes = [Schemes.http, Schemes.https];
	openApi.produces = router.mime;
	openApi.consumes = router.mime;
	openApi.definitions = errorDefinitions;

	auto routes = router.allRoutes;

	foreach (string key, schema; routes.schemas)
	{
		openApi.definitions[key] = Schema(schema);
	}

	foreach (string definedPath, methods; routes.paths)
	{
		string path = definedPath.toOpenApiPath;
		openApi.paths[path] = Path();

		foreach (method, responses; methods)
		{
			string strMethod = method.to!string.toLower;
			openApi.paths[path].operations[Path.strToType(strMethod)] = Operation();

			foreach (response, pathDefinition; responses)
			{
				string strResponse = response.to!string;
				openApi.paths[path].operations[strMethod].responses[strResponse] = swaggerize.definitions.Response();

				if (pathDefinition.schemaName != "")
				{
					openApi.paths[path][strMethod].responses[strResponse].schema = Schema(
							Json.emptyObject);
					openApi.paths[path][strMethod].responses[strResponse].schema.fields["$ref"]
						= "#/definitions/" ~ pathDefinition.schemaName;
				}

				if (pathDefinition.operation.isItemOperation)
				{
					openApi.paths[path].operations[strMethod].parameters = [itemId];
					openApi.paths[path][strMethod].responses["404"] = notFoundResponse;
					openApi.paths[path][strMethod].responses["500"] = errorResponse;
				}

				if (pathDefinition.schemaBody != "")
				{
					openApi.paths[path].operations[strMethod].parameters ~= bodyParameter(
							pathDefinition.schemaBody);
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
	parameter.in_ = Parameter.In.path;
	parameter.required = true;
	parameter.description = "The item id";
	parameter.other = Json.emptyObject;
	parameter.other["type"] = "string";

	return parameter;
}

private Parameter bodyParameter(string name)
{
	auto addParameter = Parameter();
	addParameter.in_ = Parameter.In.body_;
	addParameter.schema = Schema(Json.emptyObject);
	addParameter.name = name;
	addParameter.required = true;
	addParameter.schema.fields["$ref"] = "#/definitions/" ~ name;

	return addParameter;
}

private swaggerize.definitions.Response[string] standardResponses()
{
	swaggerize.definitions.Response[string] responses;

	auto okResponse = swaggerize.definitions.Response();
	okResponse.description = "success";

	auto errorResponse = swaggerize.definitions.Response();
	errorResponse.description = "server error";
	errorResponse.schema.fields = Json.emptyObject;
	errorResponse.schema.fields["$ref"] = "#/definitions/ErrorList";

	responses["200"] = okResponse;
	responses["404"] = notFoundResponse;
	responses["500"] = errorResponse;

	return responses;
}

private swaggerize.definitions.Response notFoundResponse()
{
	auto notFoundResponse = swaggerize.definitions.Response();
	notFoundResponse.description = "not found";
	notFoundResponse.schema.fields = Json.emptyObject;
	notFoundResponse.schema.fields["$ref"] = "#/definitions/ErrorList";

	return notFoundResponse;
}

private swaggerize.definitions.Response errorResponse()
{
	auto errorResponse = swaggerize.definitions.Response();
	errorResponse.description = "server error";
	errorResponse.schema.fields = Json.emptyObject;
	errorResponse.schema.fields["$ref"] = "#/definitions/ErrorList";

	return errorResponse;
}

private Schema[string] errorDefinitions()
{
	Schema[string] errors;

	Schema error = Schema(Json.emptyObject);
	Schema errorList = Schema(Json.emptyObject);

	errorList.fields["type"] = "object";
	errorList.fields["properties"] = Json.emptyObject;
	errorList.fields["properties"]["errors"] = Json.emptyObject;
	errorList.fields["properties"]["errors"]["type"] = "array";
	errorList.fields["properties"]["errors"]["items"] = Json.emptyObject;
	errorList.fields["properties"]["errors"]["items"]["$ref"] = "#/definitions/Error";

	error.fields["type"] = "object";
	error.fields["properties"] = Json.emptyObject;
	error.fields["properties"]["status"] = Json.emptyObject;
	error.fields["properties"]["status"]["type"] = "integer";
	error.fields["properties"]["status"]["format"] = "int32";
	error.fields["properties"]["title"] = Json.emptyObject;
	error.fields["properties"]["title"]["type"] = "string";
	error.fields["properties"]["description"] = Json.emptyObject;
	error.fields["properties"]["description"]["type"] = "string";

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

	class TestCrate(T) : Crate!T
	{
		TestModel item;

		CrateConfig!T config() {
			return CrateConfig!T();
		}

		ICrateSelector get() {
			assert(false, "not implemented");
		}

		Json[] getList(string[string])
		{
			return [item.serializeToJson];
		}

		Json addItem(Json)
		{
			throw new Exception("addItem not implemented");
		}

		Json getItem(string)
		{
			return item.serializeToJson;
		}

		Json editItem(string, Json fields)
		{
			item.name = fields["name"].to!string;
			return item.serializeToJson;
		}

		void updateItem(Json)
		{

		}

		void deleteItem(string)
		{
			throw new Exception("deleteItem not implemented");
		}
	}
}

@("Check if all the routes are defined")
unittest
{
	auto router = new URLRouter();
	auto crate = new TestCrate!TestModel;

	auto crateRouter = router
											.crateSetup
												.add(crate)
												.enableAction!(TestCrate!TestModel, "action")
												.enableAction!(TestCrate!TestModel, "actionResponse");

	auto api = crateRouter.toOpenApi;

	assert(api.paths.length == 4);
	assert(Path.OperationsType.get in api.paths["/testmodels/{id}/action"].operations);
	assert(api.paths["/testmodels/{id}/action"]["get"].parameters.length == 1);
	assert(api.paths["/testmodels/{id}/action"]["get"].parameters[0].name == "id");

	assert("ErrorList" in api.definitions);
	assert("Error" in api.definitions);
	assert("TestModelList" in api.definitions);
	assert("TestModelResponse" in api.definitions);
	assert("TestModelRequest" in api.definitions);
	assert(Path.OperationsType.get in api.paths["/testmodels/{id}/actionResponse"].operations);
}

@("Check if the array property has the right definition")
unittest
{
	auto router = new URLRouter();
	auto crate = new TestCrate!TestModel;

	auto crateRouter = router.crateSetup!CrateJsonApiPolicy.add(crate);

	auto api = crateRouter.toOpenApi.serializeToJson;

	api["definitions"]["TestModelAttributes"]["properties"]["tags"]["type"].to!string
		.should.equal("array");

	api["definitions"]["TestModelAttributes"]["properties"]["tags"]["items"]["type"].to!string
		.should.equal("string");

	api["definitions"]["TestModelAttributes"]["properties"]["list"]["type"].to!string
		.should.equal("array");

	api["definitions"]["TestModelAttributes"]["properties"]["list"]["items"]["$ref"].to!string
		.should.equal("#/definitions/NestedModel");
}

@("Check if the nested property has the right definition")
unittest
{
	auto router = new URLRouter();
	auto crate = new TestCrate!TestModel;

	auto crateRouter = router.crateSetup!CrateJsonApiPolicy.add(crate);

	auto api = crateRouter.toOpenApi.serializeToJson;

	api["definitions"]["NestedModel"]["properties"]["name"]["type"].to!string.should.equal("string");
	api["definitions"]["NestedModel"]["properties"]["other"]["$ref"].to!string
		.should.equal("#/definitions/OtherNestedModel");
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
