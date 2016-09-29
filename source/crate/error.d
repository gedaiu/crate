module crate.error;

class CrateException : Exception
{
	int statusCode = 500;
	string title = "Crate error";

	this(string msg = null, Throwable next = null)
	{
		super(msg, next);
	}

	this(string msg, string file, size_t line, Throwable next = null)
	{
		super(msg, file, line, next);
	}
}

class CrateNotFoundException : CrateException
{
	this(string msg = null, Throwable next = null)
	{
		super(msg, next);

		statusCode = 404;
		title = "Crate not found";
	}

	this(string msg, string file, size_t line, Throwable next = null)
	{
		super(msg, file, line, next);

		statusCode = 404;
		title = "Crate not found";
	}
}

class CrateRelationNotFoundException : CrateException
{
	this(string msg = null, Throwable next = null)
	{
		super(msg, next);

		statusCode = 400;
		title = "Crate relation id missing";
	}

	this(string msg, string file, size_t line, Throwable next = null)
	{
		super(msg, file, line, next);

		statusCode = 400;
		title = "Crate relation id missing";
	}
}

class CrateValidationException : CrateException
{
	this(string msg = null, Throwable next = null)
	{
		super(msg, next);

		statusCode = 403;
		title = "Validation error";
	}

	this(string msg, string file, size_t line, Throwable next = null)
	{
		super(msg, file, line, next);

		statusCode = 403;
		title = "Validation error";
	}
}

class CrateToMannyRequestsException : CrateException
{
	this(string msg = null, Throwable next = null)
	{
		super(msg, next);

		statusCode = 429;
		title = "Too many requests";
	}

	this(string msg, string file, size_t line, Throwable next = null)
	{
		super(msg, file, line, next);

		statusCode = 429;
		title = "Too many requests";
	}
}

auto toJson(Exception exception) {
	import vibe.data.json;
	auto e = cast(CrateException) exception;

	Json data = Json.emptyObject;
	data["errors"] = Json.emptyArray;
	data["errors"] ~= Json.emptyObject;

	data["errors"][0]["status"] = e is null ? 500 : e.statusCode;
	data["errors"][0]["title"] = e is null ? "Server error" : e.title;
	data["errors"][0]["description"] = exception.msg;

	return data;
}

@("Convert Crate Exception to json")
unittest {
	auto exception = new CrateException("message");
	exception.statusCode = 400;
	exception.title = "title";

	auto data = exception.toJson;

	assert(data["errors"].length == 1);
	assert(data["errors"][0]["title"] == "title");
	assert(data["errors"][0]["description"] == "message");
	assert(data["errors"][0]["status"] == 400);
}

@("Convert Exception to json")
unittest {
	auto exception = new Exception("message");

	auto data = exception.toJson;

	assert(data["errors"].length == 1);
	assert(data["errors"][0]["title"] == "Server error");
	assert(data["errors"][0]["description"] == "message");
	assert(data["errors"][0]["status"] == 500);
}
