module crate.http.resource;

import std.traits;
import std.string;
import std.conv;

import vibe.inet.url;
import vibe.http.router;
import vibe.data.json;

import crate.base;
import crate.collection.proxy;

class Resource(T, string resourcePath)
{
	private
	{
		CrateCollection collection;
	}

	this(CrateCollection collection)
	{
		this.collection = collection;
	}

	void get(HTTPServerRequest request, HTTPServerResponse response)
	{
		response.writeBody("", 200);
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
