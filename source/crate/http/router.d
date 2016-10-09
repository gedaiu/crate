module crate.http.router;

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
import std.traits;

alias DefaultPolicy = crate.policy.restapi.CrateRestApiPolicy;


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

		void deleteItem(string id)
		{
			assert(id == "1");
		}
	}

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

CrateRouter!T crateSetup(T)(URLRouter router) {
	return new CrateRouter!T(router);
}

CrateRouter!CrateRestApiPolicy crateSetup(URLRouter router) {
	return new CrateRouter!CrateRestApiPolicy(router);
}

class CrateRouter(RouterPolicy) {

	private
	{
		URLRouter router;
		CrateRoutes definedRoutes;
		CrateCollection collection;

		bool[string] mimeList;
	}

	this(URLRouter router)
	{
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


	CrateRouter enableAction(T, string actionName)()
	{
		return enableAction!(T, actionName, RouterPolicy);
	}

	CrateRouter enableAction(T, string actionName, Policy)()
	{
		auto const policy = new Policy;

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

	CrateRouter add(T)(Crate!T crate)
	{
		return add!RouterPolicy(crate);
	}

	private
	{
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
}

@("REST API tests")
unittest
{
	import crate.policy.restapi;
	import std.stdio;

	auto router = new URLRouter();
	auto baseCrate = new TestCrate!Site;
	auto relatedCrate = new TestCrate!Point;

	router
		.crateSetup
			.add(baseCrate)
			.add(relatedCrate);

	Json data = `{
		"site": {
			"latitude": 23,
			"longitude": 21
		}
	}`.parseJsonString;

	request(router)
		.get("/sites")
			.send(data)
				.expectStatusCode(200)
				.end((Response response) => {
					assert(response.bodyJson["sites"].length > 0);
					assert(response.bodyJson["sites"][0]["_id"] == "1");
				});

	request(router)
		.get("/sites/1")
			.send(data)
				.expectStatusCode(200)
				.end((Response response) => {
					assert(response.bodyJson["site"]["_id"] == "1");
				});

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
					assert(response.bodyJson["site"]["_id"] == "1");
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
