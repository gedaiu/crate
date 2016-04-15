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
