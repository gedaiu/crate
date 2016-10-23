module crate.policy.binary;

import crate.base;
import crate.serializer.raw;
import crate.generator.openapi;
import crate.ctfe;

import vibe.data.json;
import vibe.http.common;

import std.string, std.stdio, std.exception;

class BinaryPolicy : CratePolicy
	{
	private
	{
		CrateSerializer _serializer = new inout RawSerializer;
	}

	string name() inout pure nothrow
	{
		return "Binary";
	}

	inout(CrateSerializer) serializer() inout pure nothrow
	{
		return _serializer;
	}

	string mime() inout pure nothrow
	{
		return "application/json";
	}
}

CrateRoutes defineRoutes(T)(const BinaryPolicy, const CrateConfig config)
{
	CrateRoutes definedRoutes;

	definedRoutes.paths = config.paths!T;

	return definedRoutes;
}

string basePath(T)() pure
{
	return "/" ~ "name";
}

private
{
	PathDefinition[uint][HTTPMethod][string] paths(T)(const CrateConfig config)
	{
		PathDefinition[uint][HTTPMethod][string] selectedPaths;

		if (config.getList)
		{
			/*selectedPaths[basePath!T][HTTPMethod.GET][200] = PathDefinition(T.stringof ~ "List",
					"", CrateOperation.getList);*/
		}

		if (config.addItem)
		{
			selectedPaths["/resources"][HTTPMethod.POST][200] = PathDefinition("VoidResponse",
					"VoidRequest", CrateOperation.addItem);
		}

		if (config.getItem)
		{
			/*selectedPaths[basePath!T ~ "/:id"][HTTPMethod.GET][200] = PathDefinition(T.stringof ~ "Response",
					"", CrateOperation.getItem);*/
		}

		if (config.replaceItem)
		{
			/*selectedPaths[basePath!T ~ "/:id"][HTTPMethod.PATCH][200] = PathDefinition(T.stringof ~ "Response",
					T.stringof ~ "Request", CrateOperation.replaceItem);*/
		}

		if (config.deleteItem)
		{
			/*selectedPaths[basePath!T ~ "/:id"][HTTPMethod.DELETE][201] = PathDefinition("",
					"", CrateOperation.deleteItem);*/
		}

		return selectedPaths;
	}
}

@("Save a file to the drive")
unittest
{

}
