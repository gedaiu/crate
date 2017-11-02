module crate.http.action.model;

import std.traits;
import std.string;
import std.conv;

import vibe.inet.url;
import vibe.http.router;
import vibe.data.json;

import crate.base;
import crate.collection.proxy;
import crate.http.headers;
import crate.http.action.base;

class ModelAction(T: Crate!U, string actionName, U) : BaseAction!(U, actionName)
{
	private
	{
		CrateCollection collection;
	}

	this(CrateCollection collection)
	{
		this.collection = collection;
	}

	void handler(HTTPServerRequest request, HTTPServerResponse response)
	{
		auto crate = collection.getByPath(request.path);

		addItemCORS(response);
		auto item = crate.getItem(request.params["id"]).exec.front.deserializeJson!U;

		auto func = &__traits(getMember, item, actionName);

		auto result = call(request, func);

		crate.updateItem(item.serializeToJson);
		response.writeBody(result.data, result.code);
	}
}
