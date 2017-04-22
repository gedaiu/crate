module crate.http.resource;

import std.traits;
import std.string;
import std.conv;
import std.stdio;
import std.exception;

import vibe.inet.url;
import vibe.http.router;
import vibe.data.json;

import crate.base;
import crate.error;
import crate.resource;
import crate.collection.proxy;
import crate.http.headers;

private string createResourceAccess(string resourcePath) {
	auto parts = resourcePath.split("/");

	string res = "";

	foreach(part; parts) {
		if(part[0] == ':') {
			res ~= "[request.params[\"" ~ part[1 .. $] ~ "\"].to!ulong]";
		} else {
			res ~= "." ~ part;
		}
	}

	return res;
}

class Resource(T, string resourcePath)
{
	private
	{
		CrateCollection collection;
		enum resourceAccess = createResourceAccess(resourcePath);
		immutable string resourceName;
	}

	this(CrateCollection collection)
	{
		auto pathItems = resourcePath.split("/");
		resourceName = pathItems[pathItems.length - 1];
		this.collection = collection;
	}

	void get(HTTPServerRequest request, HTTPServerResponse response)
	{
		response.statusCode = 200;

		auto crate = collection.getByPath(request.path);
		addItemCORS(crate.config, response);
		auto item = crate.getItem(request.params["id"]).exec.front.deserializeJson!T;

		mixin("CrateResource obj = item" ~ resourceAccess ~ ";");

		response.headers["Content-Type"] = obj.contentType;

		if(obj.hasSize) {
			response.headers["Content-Length"] = obj.size.to!string;
		}

		obj.write(response.bodyWriter);
	}

	void post(HTTPServerRequest request, HTTPServerResponse response)
	{
		response.statusCode = 201;

		auto crate = collection.getByPath(request.path);
		addItemCORS(crate.config, response);
		auto item = crate.getItem(request.params["id"]).exec.front.deserializeJson!T;

		mixin("CrateResource obj = item" ~ resourceAccess ~ ";");

		enforce!CrateValidationException(resourceName in request.files, "`" ~ resourceName ~ "` attachement not found.");

		auto file = request.files.get(resourceName);
		obj.read(file);

		crate.updateItem(item.serializeToJson);

		response.writeBody("", 201);
	}

	private
	{
		void addItemCORS(T)(CrateConfig!T config, HTTPServerResponse response)
		{
			response.addHeaderValues("Access-Control-Allow-Origin", [ "*" ]);
			response.addHeaderValues("Access-Control-Allow-Methods", [ "OPTIONS", "GET", "POST" ]);
			response.addHeaderValues("Access-Control-Allow-Headers", [ "Content-Type" ]);
		}
	}
}
