module crate.http.action.action;

import std.traits;
import std.string;
import std.conv;

import vibe.inet.url;
import vibe.http.router;
import vibe.data.json;

import crate.base;
import crate.collection.proxy;
import crate.http.headers;

class Action(T, string actionName)
{

	private
	{
		CrateCollection collection;
	}

	this(CrateCollection collection)
	{
		this.collection = collection;
	}

	void call(HTTPServerRequest request, HTTPServerResponse response)
	{
		auto crate = collection.getByPath(request.path);

		addItemCORS(crate.config, response);
		auto item = crate.getItem(request.params["id"]).deserializeJson!T;
		auto func = &__traits(getMember, item, actionName);

		alias Param = Parameters!(__traits(getMember, T, actionName));
		alias RType = ReturnType!(__traits(getMember, T, actionName));
		string result;
		int responseCode;

		static if (Param.length == 0)
		{
			static if (is(RType == void))
			{
				func();
			}
			else
			{
				result = func().to!string;
			}

			responseCode = 200;
		}
		else static if (Param.length == 1)
		{
			string data;

			while (!request.bodyReader.empty)
			{
				ubyte[] dst;
				dst.length = request.bodyReader.leastSize.to!int;

				request.bodyReader.read(dst);
				data ~= dst.assumeUTF;
			}

			static if (is(RType == void))
			{
				func(data);
			}
			else
			{
				result = func(data).to!string;
			}

			responseCode = 201;
		}

		crate.updateItem(item.serializeToJson);
		response.writeBody(result, responseCode);
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
