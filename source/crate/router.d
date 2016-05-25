module crate.router;

import vibe.inet.url;
import vibe.http.router;
import vibe.data.json;
import vibe.data.bson;

import crate.error;
import crate.base;
import crate.ctfe;

static import crate.policy.jsonapi;
static import crate.policy.restapi;

import std.traits, std.conv, std.string, std.stdio;
import std.algorithm, std.array;

CrateRoutes routes(T)(string name, const CrateConfig config) {

	if(name == "Json API") {
		return crate.policy.jsonapi.routes!T(config);
	}

	if(name == "Rest API") {
		return crate.policy.restapi.routes!T(config);
	}

	assert(false, "Unknown " ~ name);
}

string basePath(T)(string name) {

	if(name == "Json API") {
		return crate.policy.jsonapi.basePath!T();
	}

	if(name == "Rest API") {
		return crate.policy.restapi.basePath!T();
	}

	assert(false, "Unknown " ~ name);
}

alias DefaultPolicy = crate.policy.jsonapi.CrateJsonApiPolicy;


class CrateRouter(T)
{
	private
	{
		const CratePolicy policy;
		Crate crate;

		CrateRoutes definedRoutes;
		URLRouter router;
	}

	this(URLRouter router, Crate crate, const(CratePolicy) policy = new const DefaultPolicy)
	{
		this.policy = policy;
		this.crate = crate;
		this.router = router;

		definedRoutes = routes!T(policy.name, crate.config);

		foreach (string path, methods; definedRoutes.paths)
		{
			foreach (method, responses; methods)
			{
				foreach (response, pathDefinition; responses)
				{
					addRoute(path, method, pathDefinition);
				}
			}
		}

		if (crate.config.getList || crate.config.addItem)
		{
			router.match(HTTPMethod.OPTIONS, basePath!T(policy.name), &checkError!"optionsList");
		}

		if (crate.config.getItem || crate.config.updateItem || crate.config.deleteItem)
		{
			router.match(HTTPMethod.OPTIONS, basePath!T(policy.name) ~ "/:id", &checkError!"optionsItem");
		}
	}

	void addRoute(string path, HTTPMethod method, PathDefinition definition)
	{
		switch (definition.operation)
		{
		case CrateOperation.getList:
			router.get(path, &checkError!"getList");
			break;

		case CrateOperation.getItem:
			router.get(path, &checkError!"getItem");
			break;

		case CrateOperation.addItem:
			router.post(basePath!T(policy.name), &checkError!"postItem");
			break;

		case CrateOperation.deleteItem:
			router.delete_(basePath!T(policy.name) ~ "/:id",
					&checkError!"deleteItem");
			break;

		case CrateOperation.updateItem:
			router.patch(basePath!T(policy.name) ~ "/:id",
					&checkError!"updateItem");
			break;

		case CrateOperation.replaceItem:
			router.patch(basePath!T(policy.name) ~ "/:id",
					&checkError!"updateItem");
			break;

		default:
			throw new Exception("Operation not supported: " ~ definition.operation.to!string);
		}
	}

	void checkError(string methodName)(HTTPServerRequest request, HTTPServerResponse response)
	{
		mixin("auto func = &this." ~ methodName ~ ";");

		try
		{
			try
			{
				func(request, response);
			}
			catch (CrateException e)
			{
				Json data = Json.emptyObject;
				data.errors = Json.emptyArray;
				data.errors ~= Json.emptyObject;

				data.errors[0].status = e.statusCode;
				data.errors[0].title = e.title;
				data.errors[0].description = e.msg;

				response.writeJsonBody(data, e.statusCode, policy.mime);
			}
		}
		catch (Exception e)
		{
			debug
			{
				e.writeln;
			}

			Json data = Json.emptyObject;
			data.errors = Json.emptyArray;
			data.errors ~= Json.emptyObject;

			data.errors[0].status = 500;
			data.errors[0].title = "Server error";
			data.errors[0].description = e.msg;

			response.writeJsonBody(data, 500, policy.mime);
		}
	}

	void optionsItem(HTTPServerRequest request, HTTPServerResponse response)
	{
		addItemCORS(response);
		writeln("=>", request.params["id"]);
		crate.getItem(request.params["id"]);
		response.writeBody("", 200);
	}

	void optionsList(HTTPServerRequest, HTTPServerResponse response)
	{
		addListCORS(response);
		response.writeBody("", 200);
	}

	void getItem(HTTPServerRequest request, HTTPServerResponse response)
	{
		addItemCORS(response);
		auto data = crate.getItem(request.params["id"]);

		FieldDefinition fields = getFields!T;
		auto denormalised = policy.serializer.denormalise(data, fields);

		response.writeJsonBody(denormalised, 200, policy.mime);
	}

	void updateItem(HTTPServerRequest request, HTTPServerResponse response)
	{
		addItemCORS(response);

		FieldDefinition fields = getFields!T;
		auto item = crate.getItem(request.params["id"]);

		auto newData = policy.serializer.normalise(request.json, fields);
		auto mixedData = mix(item, newData);

		crate.updateItem(mixedData);

		response.writeJsonBody(policy.serializer.denormalise(mixedData, fields), 200, policy.mime);
	}

	deprecated("Write a better mixer")
	Json mix(Json data, Json newData) {
		Json mixedData = data;

		foreach(string key, value; newData) {
			mixedData[key] = value;
		}

		return mixedData;
	}

	void deleteItem(HTTPServerRequest request, HTTPServerResponse response)
	{
		addItemCORS(response);
		crate.deleteItem(request.params["id"]);
		response.writeBody("", 204, policy.mime);
	}

	void getList(HTTPServerRequest, HTTPServerResponse response)
	{
		addListCORS(response);
		FieldDefinition fields = getFields!T;

		auto data = policy.serializer.denormalise(crate.getList, fields);

		response.writeJsonBody(data, 200, policy.mime);
	}

	void postItem(HTTPServerRequest request, HTTPServerResponse response)
	{
		addListCORS(response);

		FieldDefinition fields = getFields!T;

		auto data = policy.serializer.normalise(request.json, fields);
		auto item = policy.serializer.denormalise(crate.addItem(data), fields);

		response.headers["Location"] = (request.fullURL ~ Path(item["data"]["id"].to!string))
			.to!string;
		response.writeJsonBody(item, 201, policy.mime);
	}

	alias ActionDelegate = void delegate(T item);
	alias ActionQueryDelegate = string delegate(T item);

	void enableAction(string actionName)()
	{
		static if (__traits(hasMember, T, actionName))
		{
			alias Param = Parameters!(__traits(getMember, T, actionName));
			alias RType = ReturnType!(__traits(getMember, T, actionName));

			auto path = basePath!T(policy.name) ~ "/:id/" ~ actionName;

			static if (is(RType == void))
			{
				definedRoutes.paths[path][HTTPMethod.GET][200] = PathDefinition("",
						"", CrateOperation.otherItem);
			}
			else
			{
				definedRoutes.paths[path][HTTPMethod.GET][200] = PathDefinition("StringResponse",
						"", CrateOperation.otherItem);
			}

			static if (Param.length == 0)
			{
				router.get(path, &checkError!("callCrateAction!\"" ~ actionName ~ "\""));
			}
			else
			{
				pragma(msg, "There is no action named `" ~ actionName ~ "`");
			}
		}
		else
		{
			static assert(false, T.stringof ~ " has no `" ~ actionName ~ "` member.");
		}
	}

	void callCrateAction(string actionName)(HTTPServerRequest request, HTTPServerResponse response)
	{
		addItemCORS(response);
		auto item = crate.getItem(request.params["id"]).deserializeJson!T;
		auto func = &__traits(getMember, item, actionName);

		alias RType = ReturnType!(__traits(getMember, T, actionName));
		string result;

		static if (is(RType == void))
		{
			func();
		}
		else
		{
			result = func().to!string;
		}

		crate.updateItem(item.serializeToJson);
		response.writeBody(result, 200);
	}

	CrateRoutes allRoutes()
	{
		return definedRoutes;
	}

	string[] mime()
	{
		return [policy.mime];
	}

	private
	{
		void addListCORS(HTTPServerResponse response)
		{
			string methods = "OPTIONS";

			if (crate.config.getList)
			{
				methods ~= ", GET";
			}

			if (crate.config.addItem)
			{
				methods ~= ", POST";
			}

			response.headers["Access-Control-Allow-Origin"] = "*";
			response.headers["Access-Control-Allow-Methods"] = methods;
			response.headers["Access-Control-Allow-Headers"] = "Content-Type";
		}

		void addItemCORS(HTTPServerResponse response)
		{
			string methods = "OPTIONS";

			if (crate.config.getList)
			{
				methods ~= ", GET";
			}

			if (crate.config.updateItem)
			{
				methods ~= ", PATCH";
			}

			if (crate.config.deleteItem)
			{
				methods ~= ", DELETE";
			}

			response.headers["Access-Control-Allow-Origin"] = "*";
			response.headers["Access-Control-Allow-Methods"] = methods;
			response.headers["Access-Control-Allow-Headers"] = "Content-Type";
		}
	}
}

version (unittest)
{
	import crate.request;

	struct TestModel
	{
		@optional string _id = "1";
		string name = "";

		void actionChange()
		{
			name = "changed";
		}
	}

	class TestCrate : Crate
	{
		TestModel item;

		CrateConfig config()
		{
			return CrateConfig();
		}

		Json[] getList()
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
			item.name = fields.name.to!string;

			return item.serializeToJson;
		}

		void updateItem(Json item)
		{
			this.item.name = item.name.to!string;
		}

		void deleteItem(string)
		{
			throw new Exception("deleteItem not implemented");
		}
	}
}

@("Check and action with a string response")
unittest
{
	auto router = new URLRouter();
	auto crate = new TestCrate();
	auto crateRouter = new CrateRouter!TestModel(router, crate);

	crateRouter.enableAction!"actionChange";

	request(router).get("/testmodels/1/actionChange").expectStatusCode(200)
		.end((Response response) => {
			auto value = crate.getItem("1");
			assert(value.name == "changed");
		});
}

@("check post with relations")
unittest
{
	struct RelatedModel {
		string _id;

		string name;
	}

	struct BaseModel {
		string _id;

		string name;
		RelatedModel relation;
	}

	class BaseCrate : Crate
	{
		CrateConfig config()
		{
			return CrateConfig();
		}

		Json[] getList()
		{
			throw new Exception("getList not implemented");
		}

		Json addItem(Json item)
		{
			item["_id"] = "1";
			return item;
		}

		Json getItem(string id)
		{
			throw new Exception("getItem not implemented");
		}

		Json editItem(string id, Json fields)
		{
			throw new Exception("editItem not implemented");
		}

		void updateItem(Json item)
		{
			throw new Exception("updateItem not implemented");
		}

		void deleteItem(string id)
		{
			throw new Exception("deleteItem not implemented");
		}
	}

	auto router = new URLRouter();
	auto crate = new BaseCrate();
	auto crateRouter = new CrateRouter!BaseModel(router, crate);

	Json data = `{
		"data": {
			"attributes": {
				"name": "hello"
			},
			"type": "basemodels",
			"relationships": {
				"relation": {
					"data": {
						"type": "relatedmodels",
						"id": "1"
					}
				}
			}
		}
	}`.parseJsonString;

	request(router)
		.post("/basemodels")
		.send(data)
		.end((Response response) => {
			assert(response.bodyJson["data"]["id"] == "1");
			assert(response.bodyJson["data"]["relationships"]["relation"]["data"]["id"] == "1");
		});
}
