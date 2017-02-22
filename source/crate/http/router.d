module crate.http.router;

import crate.error;
import crate.base;
import crate.ctfe;
import crate.collection.proxy;
import crate.http.methodcollection;
import crate.http.action;
import crate.http.resource;

import crate.policy.jsonapi;
import crate.policy.restapi;

import vibe.data.json;
import vibe.http.router;

import std.conv;
import std.traits;
import std.stdio;

alias DefaultPolicy = crate.policy.restapi.CrateRestApiPolicy;

string basePath(T)(string name)
{
	static if (isAggregateType!T)
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

	assert(false, "Unknown policy `" ~ name ~ "`");
}

auto crateSetup(T)(URLRouter router) {
	return new CrateRouter!T(router);
}

auto crateSetup(URLRouter router) {
	return new CrateRouter!CrateRestApiPolicy(router);
}

private static CrateCollection[URLRouter] proxyCollection;

class CrateRouter(RouterPolicy) {

	private
	{
		URLRouter router;
		CrateRoutes definedRoutes;

		bool[string] mimeList;
	}

	this(URLRouter router)
	{
		this.router = router;

		if(router !in proxyCollection) {
			proxyCollection[router] = new CrateCollection();
		}
	}

	CrateRouter enableResource(T, string resourcePath)()
	{
		return enableResource!(T, resourcePath, RouterPolicy);
	}

	CrateRouter enableResource(T, string resourcePath, Policy)()
	{
		auto const policy = new Policy;

		auto path = basePath!T(policy.name) ~ "/:id/" ~ resourcePath;
		auto resource = new Resource!(T, resourcePath)(proxyCollection[router]);

		router.get(path, checkError(policy, &resource.get));
		router.post(path, checkError(policy, &resource.post));

		return this;
	}

	CrateRouter enableAction(T, string actionName)()
	{
		return enableAction!(T, actionName, RouterPolicy);
	}

	CrateRouter enableAction(T, string actionName, Policy)()
	{
		auto const policy = new Policy;

		auto action = new Action!(T, actionName)(proxyCollection[router]);

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

				router.get(path, checkError(policy, func));
			}
			else static if (Param.length == 1)
			{
				auto func = &action.call;

				router.post(path, checkError(policy, func));
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

		return this;
	}

	CrateRoutes allRoutes()
	{
		return definedRoutes;
	}

	string[] mime()
	{
		return mimeList.keys;
	}

	CrateRouter add(Policy, T)(Crate!T crate)
	{
		const policy = new const Policy;

		mimeList[policy.mime] = true;

		auto tmpRoutes = defineRoutes!T(policy, crate.config());

		foreach (string name, schema; tmpRoutes.schemas)
		{
			definedRoutes.schemas[name] = schema;
		}

		foreach (string path, methods; tmpRoutes.paths)
			foreach (method, responses; methods)
				foreach (response, pathDefinition; responses) {
					definedRoutes.paths[path][method][response] = pathDefinition;
				}

		bindRoutes(tmpRoutes, policy, crate);

		proxyCollection[router].addByPath(basePath!T(policy.name), crate);

		return this;
	}

	CrateRouter add(T)(Crate!T crate)
	{
		return add!RouterPolicy(crate);
	}

	private
	{
		void bindRoutes(T)(CrateRoutes routes, const CratePolicy policy, Crate!T crate)
		{
			auto methodCollection = new MethodCollection!T(policy, proxyCollection[router], crate.config);

			if (crate.config.getList || crate.config.addItem)
			{
				router.match(HTTPMethod.OPTIONS, basePath!T(policy.name),
						checkError(policy, &methodCollection.optionsList));
			}

			if (crate.config.getItem || crate.config.updateItem || crate.config.deleteItem)
			{
				router.match(HTTPMethod.OPTIONS, basePath!T(policy.name) ~ "/:id",
						checkError(policy, &methodCollection.optionsItem));
			}

			foreach (string path, methods; routes.paths)
				foreach (method, responses; methods)
					foreach (response, pathDefinition; responses) {
						addRoute(policy, path, methodCollection, pathDefinition);
					}
		}

		void addRoute(T)(const CratePolicy policy, string path, MethodCollection!T methodCollection, PathDefinition definition)
		{
			switch (definition.operation)
			{
			case CrateOperation.getList:
				router.get(path, checkError(policy, &methodCollection.getList));
				break;

			case CrateOperation.getItem:
				router.get(path, checkError(policy, &methodCollection.getItem));
				break;

			case CrateOperation.addItem:
				router.post(path, checkError(policy, &methodCollection.postItem));
				break;

			case CrateOperation.deleteItem:
				router.delete_(path,
						checkError(policy, &methodCollection.deleteItem));
				break;

			case CrateOperation.updateItem:
				router.patch(path,
						checkError(policy, &methodCollection.updateItem));
				break;

			case CrateOperation.replaceItem:
				router.put(path,
						checkError(policy, &methodCollection.replaceItem));
				break;

			default:
				throw new Exception("Operation not supported: " ~ definition.operation.to!string);
			}
		}

		auto checkError(T)(const CratePolicy policy, T func)
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
					version(unittest) {} else debug stderr.writeln(e);
					response.writeJsonBody(data, data["errors"][0]["status"].to!int, policy.mime);
				}

			}

			return &check;
		}
	}
}

version (unittest)
{
	import crate.base;
	import http.request;
	import vibe.data.json;
	import vibe.data.bson;
	import crate.collection.memory;
	import bdd.base;

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

	class TestCrate(T) : MemoryCrate!T
	{
		void action() {}
	}

	struct Point
	{
		string type = "Point";
		float[2] coordinates;
	}

	struct Site
	{
		string _id = "1";
		Point position;

		Json toJson() const {
			Json data = Json.emptyObject;

			data["_id"] = _id;
			data["position"] = position.serializeToJson;

			return data;
		}

		static Site fromJson(Json src) {
			return Site(
				src["_id"].to!string,
				Point("Point", [ src["position"]["coordinates"][0].to!int, src["position"]["coordinates"][1].to!int ])
			);
		}
	}
}

@("REST API tests")
unittest
{
	import crate.policy.restapi;
	import std.stdio;

	auto router = new URLRouter();
	auto baseCrate = new TestCrate!Site;

	router
		.crateSetup
			.add(baseCrate)
				.enableAction!(TestCrate!Site, "action");

	Json data = `{
			"position": {
				"type": "Point",
				"coordinates": [0, 0]
			}
	}`.parseJsonString;

	baseCrate.addItem(data);

	request(router)
		.get("/sites")
			.expectStatusCode(200)
			.end((Response response) => {
				response.bodyJson["sites"].length.should.be.graterThan(0);
				response.bodyJson["sites"][0]["_id"].to!string.should.equal("1");
			});

	request(router)
		.get("/sites/1")
			.expectStatusCode(200)
			.end((Response response) => {
				assert(response.bodyJson["site"]["_id"] == "1");
			});

	data = `{
		"site": {
			"latitude": "0",
			"longitude": "0"
		}
	}`.parseJsonString;

	request(router)
		.post("/sites")
			.send(data)
				.expectStatusCode(403)
				.end((Response response) => {
					assert(response.bodyJson["errors"][0]["title"] == "Validation error");
				});

	data = `{
		"site": {
			"position": {
				"type": "Point",
				"coordinates": [23, 21]
			}
		}
	}`.parseJsonString;

	request(router)
		.post("/sites")
			.send(data)
				.expectStatusCode(201)
				.end((Response response) => {
					assert(response.bodyJson["site"]["_id"] == "2");
				});

	data = `{
		"site": {
			"position": {
				"type": "Point",
				"coordinates": [0, 1]
			}
		}
	}`.parseJsonString;

	request(router)
		.put("/sites/1")
			.send(data)
				.expectStatusCode(200)
				.end((Response response) => {
					assert(response.bodyJson["site"]["position"]["coordinates"][0] == 0);
					assert(response.bodyJson["site"]["position"]["coordinates"][1] == 1);
				});

	request(router)
		.delete_("/sites/1")
			.expectStatusCode(204)
			.end((Response response) => {
			});
}
