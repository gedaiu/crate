module crate.collection.binary;

import crate.base;
import crate.error;

import vibe.inet.url;
import vibe.http.router;
import vibe.data.json;

import std.conv, std.stdio, std.exception;

class BinaryCrate(alias Name) : Crate!string
{
	private
	{
		CrateConfig _config;
	}

	this(CrateConfig config = CrateConfig(false, true, true, true, true, false))
	{
		enforce(!config.getList, "You can not have `getList` for ResourceCrate.");
		enforce(!config.updateItem, "You can not have `updateItem` for ResourceCrate.");

		this._config = config;
	}

	CrateConfig config()
	{
		return _config;
	}

	Json[] getList()
	{
		throw new Exception("Not supported");
	}

	Json addItem(Json item)
	{
		throw new Exception("Not implemented");
	}

	Json getItem(string id)
	{
		throw new Exception("Not implemented");
	}

	Json editItem(string id, Json fields)
	{
		throw new Exception("Not implemented");
	}

	void updateItem(Json item)
	{
		throw new Exception("Not implemented");
	}

	void deleteItem(string id)
	{
		throw new Exception("Not implemented");
	}
}

version (unittest)
{
	import crate.request;
	import crate.http.router;
	import crate.policy.binary;
}

@("catch config exceptions")
unittest
{
	auto router = new URLRouter();

	bool err = false;
	try
	{
		CrateConfig config;
		config.getList = true;
		config.updateItem = false;

		new BinaryCrate!"Files"(config);
	}
	catch (Exception e)
	{
		err = true;
	}

	assert(err, "Expected exception on crate init");

	err = false;
	try
	{
		CrateConfig config;
		config.getList = false;
		config.updateItem = true;

		new BinaryCrate!"Files"(config);
	}
	catch (Exception e)
	{
		err = true;
	}

	assert(err, "Expected exception on crate init");

	err = false;
	try
	{
		new BinaryCrate!"Files"();
	}
	catch (Exception e)
	{
		err = true;
	}

	assert(!err, "Expected exception on crate init");
}

unittest
{
	auto router = new URLRouter();
	auto crate = new BinaryCrate!"Files"();

	router
		.crateSetup!BinaryPolicy
			.add(crate);

	auto data = `--AaB03x
content-disposition: form-data; name="content"

content`;

	request(router)
		.header("Content-Length", data.length.to!string)
		.header("Content-Type", "multipart/form-data; boundary=AaB03x")
		.post("/resources")
			.send(data)
				.end((Response response) => {
					response.writeln;
				});
}
