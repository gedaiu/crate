module crate.http.resource;

import std.traits;
import std.string;
import std.conv;
import std.stdio;

import vibe.inet.url;
import vibe.http.router;
import vibe.data.json;

import crate.base;
import crate.error;
import crate.resource;
import crate.collection.proxy;

class Resource(T, string resourcePath)
{
	private
	{
		CrateCollection collection;
		enum resourceAccess = resourcePath.split("/").join(".");
		enum resourceName = "resource";
	}

	this(CrateCollection collection)
	{
		this.collection = collection;
	}

	void get(HTTPServerRequest request, HTTPServerResponse response)
	{
		response.statusCode = 200;

		auto crate = collection.getByPath(request.path);
		addItemCORS(crate.config, response);
		auto item = crate.getItem(request.params["id"]).deserializeJson!T;

		mixin("CrateResource obj = item." ~ resourceAccess ~ ";");

		response.headers["Content-Type"] = obj.contentType;
		response.headers["Content-Length"] = obj.size.to!string;
		obj.write(response.bodyWriter);
	}

	void post(HTTPServerRequest request, HTTPServerResponse response)
	{
		response.statusCode = 201;

		auto crate = collection.getByPath(request.path);
		addItemCORS(crate.config, response);
		auto item = crate.getItem(request.params["id"]).deserializeJson!T;

		mixin("CrateResource obj = item." ~ resourceAccess ~ ";");

		enforce!CrateValidationException(resourceName in request.files, "`" ~ resourceName ~ "` not found.");

		auto file = request.files.get(resourceName);
		obj.read(file);

		response.writeBody("", 201);
	}

	private
	{
		void addItemCORS(CrateConfig config, HTTPServerResponse response)
		{
			response.headers["Access-Control-Allow-Origin"] = "*";
			response.headers["Access-Control-Allow-Methods"] = "OPTIONS, GET, POST";
			response.headers["Access-Control-Allow-Headers"] = "Content-Type";
		}
	}
}
