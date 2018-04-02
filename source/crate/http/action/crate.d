module crate.http.action.crate;

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

class CrateAction(T: Crate!U, string actionName, U) : BaseAction!(T, actionName)
{
	private
	{
		T crate;
	}

	this(T crate)
	{
		this.crate = crate;
	}

	void handler(HTTPServerRequest request, HTTPServerResponse response)
	{
		addItemCORS(response);

		auto func = &__traits(getMember, crate, actionName);
		alias Param = Parameters!(__traits(getMember, T, actionName));
		alias RType = ReturnType!(__traits(getMember, T, actionName));

		auto result = call(request, func);

		response.writeBody(result.data, result.code);
	}
}
