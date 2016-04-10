module crate.request;

import vibe.inet.url;
import vibe.http.router;
import vibe.data.json;

import std.conv, std.string;

RequestRouter request(URLRouter router)
{
	return new RequestRouter(router);
}

final class RequestRouter
{
	private
	{
		URLRouter router;
		HTTPServerRequest preparedRequest;

    string[string] expectHeaders;
    string[string] expectHeadersContains;
    int expectedStatusCode;
	}

	this(URLRouter router)
	{
		this.router = router;
	}

	RequestRouter send(T)(T data)
	{
		static if (is(T == string))
		{
			return this;
		}
		else static if (is(T == Json))
		{
			return send(data.to!string);
		}
		else
		{
			return send(data.serializeToJson());
		}
	}

	RequestRouter post(string path)
	{
		return request!(HTTPMethod.POST)(URL("http://localhost" ~ path));
	}

	RequestRouter request(HTTPMethod method)(URL url)
	{
		preparedRequest = createTestHTTPServerRequest(url, method);

		return this;
	}

	RequestRouter expectHeader(string name, string value)
	{
    expectHeaders[name] = value;
		return this;
	}

	RequestRouter expectHeaderContains(string name, string value)
	{
    expectHeadersContains[name] = value;
		return this;
	}

	RequestRouter expectStatusCode(int code)
	{
    expectedStatusCode =  code;
		return this;
	}

  private void performExpected(HTTPServerResponse res) {

    if(expectedStatusCode != 0) {
      assert(expectedStatusCode == res.statusCode, "Expected status code `" ~ expectedStatusCode.to!string ~ "` not found. Got `" ~ res.statusCode.to!string ~ "` instead");
    }

    foreach(string key, value; expectHeaders) {
      assert(key in res.headers, "Response header `" ~ key ~ "` is missing.");
      assert(res.headers[key] == value, "Response header `" ~ key ~ "` has an unexpected value. Expected `" ~ value ~ "` != `" ~ res.headers[key].to!string ~ "`");
    }

    foreach(string key, value; expectHeadersContains) {
      assert(key in res.headers, "Response header `" ~ key ~ "` is missing.");
      assert(res.headers[key].indexOf(value) != -1, "Response header `" ~ key ~ "` has an unexpected value. Expected `" ~ value ~ "` not found in `" ~ res.headers[key].to!string ~ "`");
    }

  }

	void end(T)(T callback)
	{
		HTTPServerResponse res = createTestHTTPServerResponse();
		res.statusCode = 404;

		router.handleRequest(preparedRequest, res);

    performExpected(res);

		callback(res)();
	}

	void end(alias T)()
	{
		HTTPServerResponse res;
		router.handleRequest(preparedRequest, res);

    performExpected(res);

		T(res);
	}
}
