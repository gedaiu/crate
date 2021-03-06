module crate.http.action.base;

import std.traits;
import std.string;
import std.conv;

import vibe.inet.url;
import vibe.http.router;
import vibe.data.json;

import crate.base;
import crate.collection.proxy;
import crate.http.headers;

struct ActionResult {
	string data;
	int code;
}

class BaseAction(T, string actionName)
{
	HTTPMethod method() {
		static if (Param.length == 0)
		{
			return HTTPMethod.GET;
		}
		else
		{
			return HTTPMethod.POST;
		}
	}

	string returnType() {
		static if (is(RType == void))
		{
			return "";
		}
		else
		{
			return "StringResponse";
		}
	}

	protected
	{
		alias Param = Parameters!(__traits(getMember, T, actionName));
		alias RType = ReturnType!(__traits(getMember, T, actionName));

		void addItemCORS(HTTPServerResponse response)
		{
			response.addHeaderValues("Access-Control-Allow-Origin", [ "*" ]);
			response.addHeaderValues("Access-Control-Allow-Methods", [ "OPTIONS", "GET", "POST" ]);
			response.addHeaderValues("Access-Control-Allow-Headers", [ "Content-Type" ]);
		}

		auto call(F)(HTTPServerRequest request, F func) {
			ActionResult result;

			static if (Param.length == 0)
			{
				static if (is(RType == void))
				{
					func();
				}
				else
				{
					result.data = func().to!string;
				}

				result.code = 200;
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
					alias PT = Parameters!func[0];
					func(data.to!PT);
				}
				else
				{
					result.data = func(data).to!string;
				}

				result.code = 201;
			}

			return result;
		}
	}
}
