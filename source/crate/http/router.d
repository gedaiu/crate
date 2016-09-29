module crate.http.router;

import std.exception;

import vibe.inet.url;
import vibe.http.router;
import vibe.data.json;
import vibe.data.bson;

import crate.error;
import crate.base;
import crate.ctfe;
import crate.collection.proxy;
import crate.http.methodcollection;
import crate.http.action;

static import crate.policy.jsonapi;
static import crate.policy.restapi;
static import crate.policy.raw;

import std.traits, std.conv, std.string, std.stdio;
import std.algorithm, std.array, std.traits, std.meta;

string basePath(T)(string name)
{
	static if (is(Crate!T.Conversion == Json))
	{
		if (name == "Json API")
		{
			return crate.policy.jsonapi.basePath!T;
		}

		if (name == "Rest API")
		{
			return crate.policy.restapi.basePath!T;
		}
	}
	else
	{
		return crate.policy.raw.basePath(name);
	}

	assert(false, "Unknown " ~ name);
}

alias DefaultPolicy = crate.policy.jsonapi.CrateJsonApiPolicy;

class CrateRouter
{
	const CratePolicy policy;

	private
	{
		CrateCollection collection;
		CrateRoutes definedRoutes;
		URLRouter router;
	}

	this(T...)(URLRouter router, const(CratePolicy) policy, T crates)
	{
		this.policy = policy;
		this.router = router;
		this.collection = CrateCollection();

		foreach (crate; crates)
		{
			addCrate(crate);
		}
	}

	this(U, T...)(URLRouter router, Crate!U firstCrate, T crates)
	{
		this.policy = new const DefaultPolicy;
		this.router = router;
		this.collection = CrateCollection();

		addCrate(firstCrate);

		foreach (crate; crates)
		{
			addCrate(crate);
		}
	}

	this(T)(URLRouter router, Crate!T crate, const(CratePolicy) policy = new const DefaultPolicy)
	{
		this(router, policy, crate);
	}

	alias Types = AliasSeq!();

	void addCrate(T)(Crate!T crate)
	{
		auto tmpRoutes = routes(policy.name, crate);

		foreach (string name, schema; tmpRoutes.schemas)
		{
			definedRoutes.schemas[name] = schema;
		}

		foreach (string path, methods; tmpRoutes.paths)
			foreach (method, responses; methods)
				foreach (response, pathDefinition; responses)
					definedRoutes.paths[path][method][response] = pathDefinition;

		bindRoutes(crate);
	}

	void bindRoutes(T)(Crate!T crate)
	{
		auto methodCollection = new MethodCollection(policy, collection, crate.config);

		if (crate.config.getList || crate.config.addItem)
		{
			router.match(HTTPMethod.OPTIONS, basePath!T(policy.name),
					checkError(&methodCollection.optionsList));
		}

		if (crate.config.getItem || crate.config.updateItem || crate.config.deleteItem)
		{
			router.match(HTTPMethod.OPTIONS, basePath!T(policy.name) ~ "/:id",
					checkError(&methodCollection.optionsItem));
		}

		foreach (string path, methods; definedRoutes.paths)
			foreach (method, responses; methods)
				foreach (response, pathDefinition; responses)
					addRoute(path, methodCollection, pathDefinition);
	}

	CrateRoutes routes(T)(string name, Crate!T localCrate)
	{
		static if (is(Crate!T.Conversion == Json))
		{
			if (name == "Json API")
			{
				collection.addByPath(basePath!T(policy.name), localCrate);

				return crate.policy.jsonapi.routes!T(localCrate.config);
			}

			if (name == "Rest API")
			{
				collection.addByPath(basePath!T(policy.name), localCrate);

				return crate.policy.restapi.routes!T(localCrate.config);
			}
		}
		else
		{
			pragma(msg, "\nCan not use selected policy for `Crate!", T.stringof, "`");
			pragma(msg, "Using raw policy instead\n");

			return crate.policy.raw.routes!T(localCrate.config);
		}

		assert(false, "Unknown " ~ name);
	}

	void addRoute(string path, MethodCollection methodCollection, PathDefinition definition)
	{
		switch (definition.operation)
		{
		case CrateOperation.getList:
			router.get(path, checkError(&methodCollection.getList));
			break;

		case CrateOperation.getItem:
			router.get(path, checkError(&methodCollection.getItem));
			break;

		case CrateOperation.addItem:
			router.post(path, checkError(&methodCollection.postItem));
			break;

		case CrateOperation.deleteItem:
			router.delete_(path,
					checkError(&methodCollection.deleteItem));
			break;

		case CrateOperation.updateItem:
			router.patch(path,
					checkError(&methodCollection.updateItem));
			break;

		case CrateOperation.replaceItem:
			router.put(path,
					checkError(&methodCollection.replaceItem));
			break;

		default:
			throw new Exception("Operation not supported: " ~ definition.operation.to!string);
		}
	}

	auto checkError(T)(T func)
	{
		void check(HTTPServerRequest request, HTTPServerResponse response)
		{
			try
			{
				func(request, response);
			}
			catch (Exception e)
			{
				Json data = e.toJson;

				response.writeJsonBody(data, data["errors"][0]["status"].to!int, policy.mime);
			}
		}

		return &check;
	}

	void enableAction(T, string actionName)()
	{
		auto action = new Action!(T, actionName)(collection);

		static if (__traits(hasMember, T, actionName))
		{
			alias Param = Parameters!(__traits(getMember, T, actionName));
			alias RType = ReturnType!(__traits(getMember, T, actionName));

			auto path = basePath!T(policy.name) ~ "/:id/" ~ actionName;

			static if (is(RType == void))
			{
				string returnType = "";
			}
			else
			{
				string returnType = "StringResponse";
			}

			static if (Param.length == 0)
			{
				HTTPMethod method = HTTPMethod.GET;
			}
			else
			{
				HTTPMethod method = HTTPMethod.POST;
			}

			definedRoutes.paths[path][method][200] = PathDefinition(returnType,
					"", CrateOperation.otherItem);

			static if (Param.length == 0)
			{
				auto func = &action.call;

				router.get(path, checkError(func));
			}
			else static if (Param.length == 1)
			{
				auto func = &action.call;

				router.post(path, checkError(func));
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

	CrateRoutes allRoutes()
	{
		return definedRoutes;
	}

	string[] mime()
	{
		return [policy.mime];
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

		void actionParam(string data)
		{
			name = data;
		}
	}

	class TestCrate(T) : Crate!T
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

		Json addItem(Json item)
		{
			item["_id"] = "1";
			return item;
		}

		Json getItem(string)
		{
			return item.serializeToJson;
		}

		void updateItem(Json item)
		{
			this.item.name = item["name"].to!string;
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
	auto crate = new TestCrate!TestModel;
	auto crateRouter = new CrateRouter(router, crate);

	crateRouter.enableAction!(TestModel, "actionChange");

	request(router).get("/testmodels/1/actionChange").expectStatusCode(200)
		.end((Response response) => {
			auto value = crate.getItem("1");
			assert(value["name"] == "changed");
		});
}

@("Check and action with a string parameter")
unittest
{
	auto router = new URLRouter();
	auto crate = new TestCrate!TestModel;
	auto crateRouter = new CrateRouter(router, crate);

	crateRouter.enableAction!(TestModel, "actionParam");

	request(router).post("/testmodels/1/actionParam").send("data123")
		.expectStatusCode(201).end((Response response) => {
			auto value = crate.getItem("1");
			assert(value["name"] == "data123");
		});
}

@("check post with existing relations")
unittest
{
	struct RelatedModel
	{
		string _id;

		string name;
	}

	struct BaseModel
	{
		string _id;

		string name;
		RelatedModel relation;
	}

	auto router = new URLRouter();
	auto baseCrate = new TestCrate!BaseModel;
	auto relatedCrate = new TestCrate!RelatedModel;

	auto crateRouter = new CrateRouter(router, baseCrate, relatedCrate);

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

	request(router).post("/basemodels").send(data).end((Response response) => {
		assert(response.bodyJson["data"]["id"] == "1");
		assert(response.bodyJson["data"]["relationships"]["relation"]["data"]["id"] == "1");
	});
}

version (unittest)
{
	class MissingCrate(T) : Crate!T
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
			throw new CrateNotFoundException("getItem not implemented");
		}

		void updateItem(Json item)
		{
			throw new CrateNotFoundException("getItem not implemented");
		}

		void deleteItem(string id)
		{
			throw new CrateNotFoundException("getItem not implemented");
		}
	}
}

@("check post with missing relations")
unittest
{
	struct RelatedModel
	{
		string _id;

		string name;
	}

	struct BaseModel
	{
		string _id;

		string name;
		RelatedModel relation;
	}

	auto router = new URLRouter();
	auto baseCrate = new TestCrate!BaseModel;
	auto relatedCrate = new MissingCrate!RelatedModel;

	auto crateRouter = new CrateRouter(router, baseCrate, relatedCrate);

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

	request(router).post("/basemodels").send(data).expectStatusCode(400).end((Response response) => {
	});

	request(router).patch("/basemodels/1").send(data).expectStatusCode(400)
		.end((Response response) => {  });
}

@("check post with wrong fields")
unittest
{
	import crate.policy.restapi;

	struct Point
	{
		immutable string type = "Point";
		float[2] coordinates;
	}

	struct Site
	{
		BsonObjectID _id;

		Point position;
	}

	auto router = new URLRouter();
	auto baseCrate = new TestCrate!Site;
	auto relatedCrate = new MissingCrate!Point;

	auto crateRouter = new CrateRouter(router, new CrateRestApiPolicy(), baseCrate, relatedCrate);

	Json data = `{
		"site": {
			"latitude": 23,
			"longitude": 21
		}
	}`.parseJsonString;

	request(router).post("/sites").send(data).expectStatusCode(403).end((Response response) => {
	});

	request(router).put("/sites/1").send(data).expectStatusCode(403).end((Response response) => {
	});
}
