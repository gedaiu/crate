module crate.http.router2;

import crate.error;
import crate.base;
import crate.ctfe;
import crate.collection.proxy;
import crate.http.methodcollection;
import crate.http.action;
import crate.policy.jsonapi;
import crate.policy.restapi;

import vibe.data.json;
import vibe.http.router;

import std.conv;

alias DefaultPolicy = crate.policy.jsonapi.CrateJsonApiPolicy;


version (unittest)
{
	import crate.base;
	import crate.request;
	import vibe.data.json;
	import vibe.data.bson;

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

URLRouter addCrate(URLRouter router) {
	return router;
}

CrateRouter!T crateSetup(T)(URLRouter router) {
	return new CrateRouter!T(router);
}

class CrateRouter(RouterPolicy) {

	private {
		URLRouter router;
		CrateRoutes definedRoutes;
		CrateCollection collection;
	}

	this(URLRouter router) {
		this.collection = CrateCollection();
		this.router = router;
	}

	CrateRoutes routes(T)(const CratePolicy policy, Crate!T localCrate)
	{
		string name = policy.name;

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

	CrateRouter add(Policy, T)(Crate!T crate) {
		const policy = new const Policy;

		auto tmpRoutes = routes(policy, crate);

		foreach (string name, schema; tmpRoutes.schemas)
		{
			definedRoutes.schemas[name] = schema;
		}

		foreach (string path, methods; tmpRoutes.paths)
			foreach (method, responses; methods)
				foreach (response, pathDefinition; responses)
					definedRoutes.paths[path][method][response] = pathDefinition;

		bindRoutes(policy, crate);

		return this;
	}

	CrateRouter add(T)(Crate!T crate) {
		const policy = new const RouterPolicy;

		auto tmpRoutes = routes(policy, crate);

		foreach (string name, schema; tmpRoutes.schemas)
		{
			definedRoutes.schemas[name] = schema;
		}

		foreach (string path, methods; tmpRoutes.paths)
			foreach (method, responses; methods)
				foreach (response, pathDefinition; responses)
					definedRoutes.paths[path][method][response] = pathDefinition;

		bindRoutes(policy, crate);

		return this;
	}

	void bindRoutes(T)(const CratePolicy policy, Crate!T crate)
	{
		auto methodCollection = new MethodCollection(policy, collection, crate.config);

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

		foreach (string path, methods; definedRoutes.paths)
			foreach (method, responses; methods)
				foreach (response, pathDefinition; responses)
					addRoute(policy, path, methodCollection, pathDefinition);
	}

	void addRoute(const CratePolicy policy, string path, MethodCollection methodCollection, PathDefinition definition)
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

				response.writeJsonBody(data, data["errors"][0]["status"].to!int, policy.mime);
			}
		}

		return &check;
	}
}

@("check post with wrong fields")
unittest
{
	import crate.policy.restapi;
	import std.stdio;

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
	auto relatedCrate = new TestCrate!Point;


	router
		.crateSetup!DefaultPolicy
			.add(baseCrate)
			.add(relatedCrate);

	//auto crateRouter = new CrateRouter(router, new CrateRestApiPolicy(), baseCrate, relatedCrate);

	Json data = `{
		"site": {
			"latitude": 23,
			"longitude": 21
		}
	}`.parseJsonString;


	request(router)
		.post("/sites")
			.send(data)
			.expectStatusCode(403)
				.end((Response response) => {
					response.writeln;
				});
/*
	request(router).put("/api/sites/1").send(data).expectStatusCode(403).end((Response) => {
	});*/
}
