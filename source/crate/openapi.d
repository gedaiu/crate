module crate.openapi;

import vibe.http.router;
import crate.base;
import swaggerize.definitions;
import std.stdio, std.string;
import vibe.data.json;

Swagger toOpenApi(T)(CrateRouter!T router)
{
	Swagger openApi;
	openApi.host = "localhost";
	openApi.schemes = [ Schemes.http, Schemes.https ];
	openApi.produces = [ router.serializer.mime ];
	openApi.consumes = [ router.serializer.mime ];
	openApi.definitions = errorDefinitions;

	auto schemas = router.serializer.schemas;

	foreach(string key, schema; schemas) {
		openApi.definitions[key] = Schema(schema);
	}

	openApi.paths["/" ~ router.config.plural] = itemListPath(router);
	openApi.paths["/" ~ router.config.plural ~ "/{id}"] = itemPath(router);

	foreach(string action, hasParam; router.actions) {
		auto path = actionPath;

		if(hasParam) {
			path["get"].responses["200"].schema.fields = Json.emptyObject;
			path["get"].responses["200"].schema.fields["type"] = "string";
		}

		openApi.paths["/" ~ router.config.plural ~ "/{id}/" ~ action] = path;
	}

	return openApi;
}

private Path itemListPath(T)(CrateRouter!T router) {
	auto path = Path();

	auto optionsOperation = Operation();
	auto listOperation = Operation();
	auto addOperation = Operation();

	optionsOperation.responses["200"] = swaggerize.definitions.Response();

	listOperation.responses["200"] = swaggerize.definitions.Response();
	listOperation.responses["200"].schema = Schema(Json.emptyObject);
	listOperation.responses["200"].schema.fields["$ref"] = "#/definitions/" ~ T.stringof ~ "List";

	auto addParameter = Parameter();
	addParameter.in_ = Parameter.In.body_;
	addParameter.schema = Schema(Json.emptyObject);
	addParameter.name = T.stringof.toLower;
	addParameter.required = true;
	addParameter.schema.fields["$ref"] = "#/definitions/" ~ T.stringof ~ "Request";

	addOperation.parameters = [ addParameter ];

	addOperation.responses["201"] = swaggerize.definitions.Response();
	addOperation.responses["201"].schema = Schema(Json.emptyObject);
	addOperation.responses["201"].schema.fields["$ref"] = "#/definitions/" ~ T.stringof ~ "Response";

	path.operations["options"] = optionsOperation;
	path.operations["get"] = listOperation;
	path.operations["post"] = addOperation;

	return path;
}

private Path itemPath(T)(CrateRouter!T router) {
	auto path = Path();

	auto optionsOperation = Operation();
	auto getOperation = Operation();
	auto editOperation = Operation();
	auto deleteOperation = Operation();

	optionsOperation.parameters = [ itemId ];
	optionsOperation.responses["200"] = swaggerize.definitions.Response();

	getOperation.parameters = [ itemId ];
	getOperation.responses["200"] = swaggerize.definitions.Response();
	getOperation.responses["200"].schema = Schema(Json.emptyObject);
	getOperation.responses["200"].schema.fields["$ref"] = "#/definitions/" ~ T.stringof ~ "Response";

	getOperation.responses["404"] = notFoundResponse;

	auto editParameter = Parameter();
	editParameter.in_ = Parameter.In.body_;
	editParameter.schema = Schema(Json.emptyObject);
	editParameter.name = T.stringof.toLower;
	editParameter.required = true;
	editParameter.schema.fields["$ref"] = "#/definitions/" ~ T.stringof ~ "Request";

	editOperation.parameters = [ itemId, editParameter ];
	editOperation.responses["200"] = getOperation.responses["200"];
	editOperation.responses["404"] = notFoundResponse;

	deleteOperation.parameters = [ itemId ];
	deleteOperation.responses["201"] = swaggerize.definitions.Response();
	deleteOperation.responses["404"] = notFoundResponse;

	path.operations["options"] = optionsOperation;
	path.operations["get"] = getOperation;
	path.operations["patch"] = editOperation;
	path.operations["delete"] = deleteOperation;

	return path;
}

private Path actionPath() {
	auto actionPath = Path();
	auto operation = Operation();


	operation.tags = ["action"];
	operation.parameters ~= itemId;
	operation.responses = standardResponses;

	actionPath.operations["get"] = operation;

	return actionPath;
}

private Parameter itemId() {
	auto parameter = Parameter();
	parameter.name = "id";
	parameter.in_ = Parameter.In.path;
	parameter.required = true;
	parameter.description = "The item id";
	parameter.other = Json.emptyObject;
	parameter.other["type"] = "string";

	return parameter;
}

private swaggerize.definitions.Response[string] standardResponses() {
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

private swaggerize.definitions.Response notFoundResponse() {
	auto notFoundResponse = swaggerize.definitions.Response();
	notFoundResponse.description = "not found";
	notFoundResponse.schema.fields = Json.emptyObject;
	notFoundResponse.schema.fields["$ref"] = "#/definitions/ErrorList";

	return notFoundResponse;
}

private swaggerize.definitions.Response errorResponse() {
	auto errorResponse = swaggerize.definitions.Response();
	errorResponse.description = "server error";
	errorResponse.schema.fields = Json.emptyObject;
	errorResponse.schema.fields["$ref"] = "#/definitions/ErrorList";

	return errorResponse;
}

private Schema[string] errorDefinitions() {
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

version (unittest)
{
	import crate.request;
	import crate.router;
	import vibe.data.serialization;
	import vibe.data.json;

	bool isTestActionCalled;

	struct TestModel
	{
		@optional {
			string _id;
			string other = "";
		}

		string name = "";

		void action() {
			isTestActionCalled = true;
		}

		string actionResponse() {
			isTestActionCalled = true;
			return "ok.";
		}
	}

	class TestCrate : Crate!TestModel {
		TestModel item;

		TestModel[] getList() {
			return [ item ];
		}

		TestModel addItem(TestModel item) {
			throw new Exception("addItem not implemented");
		}

		TestModel getItem(string id) {
			return item;
		}

		TestModel editItem(string id, Json fields) {
			item.name = fields.name.to!string;

			return item;
		}

		void deleteItem(string id) {
			throw new Exception("deleteItem not implemented");
		}
	}
}

unittest
{
	auto router = new URLRouter();
	auto crate = new TestCrate;

	auto crateRouter = new CrateRouter!TestModel(router, crate);
	crateRouter.enableAction!"action";
	crateRouter.enableAction!"actionResponse";

	auto api = crateRouter.toOpenApi;

	api.serializeToJson.toPrettyString.writeln;

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
