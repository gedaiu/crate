module crate.router;

import vibe.inet.url;
import vibe.http.router;
import vibe.data.json;
import vibe.data.bson;

import crate.error;
import crate.base;
import crate.serializer.jsonapi;

import std.traits, std.conv, std.string, std.stdio;

class CrateRouter(T)
{
	private {
		CrateSerializer!T serializer;
		CrateRoutes definedRoutes;
	}

	private
	{
		Crate!T crate;
		URLRouter router;
	}

	this(URLRouter router, Crate!T crate, CrateSerializer!T serializer = new CrateJsonApiSerializer!T())
	{
		this.serializer = serializer;
		this.crate = crate;
		this.router = router;
		definedRoutes = serializer.routes;

		if (serializer.config.getList)
		{
			router.get(serializer.basePath, &checkError!"getList");
		}

		if (serializer.config.addItem)
		{
			router.post(serializer.basePath, &checkError!"postItem");
		}

		if (serializer.config.getItem)
		{
			router.get(serializer.basePath ~ "/:id", &checkError!"getItem");
		}

		if (serializer.config.updateItem)
		{
			router.patch(serializer.basePath ~ "/:id", &checkError!"updateItem");
		}

		if (serializer.config.deleteItem)
		{
			router.delete_(serializer.basePath ~ "/:id", &checkError!"deleteItem");
		}

		if (serializer.config.getList || serializer.config.addItem) {
			router.match(HTTPMethod.OPTIONS, serializer.basePath, &checkError!"optionsList");
		}

		if (serializer.config.getItem || serializer.config.updateItem || serializer.config.deleteItem) {
			router.match(HTTPMethod.OPTIONS, serializer.basePath ~ "/:id", &checkError!"optionsItem");
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

				response.writeJsonBody(data, e.statusCode, serializer.mime);
			}
		}
		catch (Exception e)
		{
			Json data = Json.emptyObject;
			data.errors = Json.emptyArray;
			data.errors ~= Json.emptyObject;

			data.errors[0].status = 500;
			data.errors[0].title = "Server error";
			data.errors[0].description = e.msg;

			response.writeJsonBody(data, 500, serializer.mime);
		}
	}

	void optionsItem(HTTPServerRequest request, HTTPServerResponse response)
	{
		addItemCORS(response);
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
		response.writeJsonBody(serializer.serialize(data), 200, serializer.mime);
	}

	void updateItem(HTTPServerRequest request, HTTPServerResponse response)
	{
		addItemCORS(response);
		auto data = crate.editItem(request.params["id"], request.json["data"].attributes);
		response.writeJsonBody(serializer.serialize(data), 200, serializer.mime);
	}

	void deleteItem(HTTPServerRequest request, HTTPServerResponse response)
	{
		addItemCORS(response);
		crate.getItem(request.params["id"]);
		crate.deleteItem(request.params["id"]);
		response.writeBody("", 204, serializer.mime);
	}

	void getList(HTTPServerRequest, HTTPServerResponse response)
	{
		addListCORS(response);
		auto data = crate.getList;
		response.writeJsonBody(serializer.serialize(data), 200, serializer.mime);
	}

	void postItem(HTTPServerRequest request, HTTPServerResponse response)
	{
		addListCORS(response);
		auto item = crate.addItem(serializer.deserialize(request.json));
		auto data = serializer.serialize(item);

		response.headers["Location"] = (request.fullURL ~ Path(data["data"]["id"].to!string))
			.to!string;
		response.writeJsonBody(data, 201, serializer.mime);
	}

	alias ActionDelegate = void delegate(T item);
	alias ActionQueryDelegate = string delegate(T item);

	void addAction(string actionName)(ActionDelegate action)
	{
		void preparedAction(HTTPServerRequest request, HTTPServerResponse response)
		{
			auto item = crate.getItem(request.params["id"]);
			action(item);

			response.writeBody("", 200, serializer.mime);
		}

		router.get(serializer.basePath ~ "/:id/" ~ actionName, &preparedAction);
	}

	void addAction(string actionName)(ActionQueryDelegate action)
	{
		void preparedAction(HTTPServerRequest request, HTTPServerResponse response)
		{
			auto item = crate.getItem(request.params["id"]);

			response.writeBody(action(item), 200, serializer.mime);
		}

		router.get(serializer.basePath ~ "/:id/" ~ actionName, &preparedAction);
	}

	void addAction(string actionName, U)(void delegate(T item, U value) action)
	{
		void preparedAction(HTTPServerRequest request, HTTPServerResponse response)
		{
			auto item = crate.getItem(request.params["id"]);
			auto value = request.json.deserializeJson!U;

			action(item, value);

			response.writeBody("", 200, serializer.mime);
		}

		router.post(serializer.basePath ~ "/:id/" ~ actionName, &preparedAction);
	}

	void addAction(string actionName, U)(string delegate(T item, U value) action)
	{
		void preparedAction(HTTPServerRequest request, HTTPServerResponse response)
		{
			auto item = crate.getItem(request.params["id"]);
			auto value = request.json.deserializeJson!U;

			response.writeBody(action(item, value), 200, serializer.mime);
		}

		router.post(serializer.basePath ~ "/:id/" ~ actionName, &preparedAction);
	}

	void enableAction(string actionName)()
	{
		static if (__traits(hasMember, T, actionName))
		{
			alias Param = Parameters!(__traits(getMember, T, actionName));
			alias RType = ReturnType!(__traits(getMember, T, actionName));

			auto path = serializer.basePath ~ "/:id/" ~ actionName;

			static if (is(RType == void))
			{
				definedRoutes.paths[path][HTTPMethod.GET][200] = "";
			}
			else
			{
				definedRoutes.paths[path][HTTPMethod.GET][200] = "StringResponse";
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
		auto item = crate.getItem(request.params["id"]);
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

		crate.editItem(request.params["id"], item.serializeToJson);
		response.writeBody(result, 200);
	}

	CrateRoutes routes() {
		return definedRoutes;
	}

	string[] mime() {
		return [ serializer.mime ];
	}

	private {
		void addListCORS(HTTPServerResponse response)
		{
			string methods = "OPTIONS";

			if (serializer.config.getList)
			{
				methods ~= ", GET";
			}

			if (serializer.config.addItem)
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

			if (serializer.config.getList)
			{
				methods ~= ", GET";
			}

			if (serializer.config.updateItem)
			{
				methods ~= ", PATCH";
			}

			if (serializer.config.deleteItem)
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

	class TestCrate : Crate!TestModel
	{
		TestModel item;

		TestModel[] getList()
		{
			return [item];
		}

		TestModel addItem(TestModel)
		{
			throw new Exception("addItem not implemented");
		}

		TestModel getItem(string)
		{
			return item;
		}

		TestModel editItem(string, Json fields)
		{
			item.name = fields.name.to!string;

			return item;
		}

		void deleteItem(string)
		{
			throw new Exception("deleteItem not implemented");
		}
	}
}

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
