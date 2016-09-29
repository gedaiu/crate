module crate.collection.resource;

import crate.base;
import crate.error;

import vibe.inet.url;
import vibe.http.router;
import vibe.data.json;

import std.conv, std.stdio;

struct S {}

class ResourceCrate : Crate!string
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

	Conversion[] getList()
	{
		throw new Exception("Not supported");
	}

	Conversion addItem(Conversion item)
	{
		throw new Exception("Not implemented");
	}

	Conversion getItem(string id)
	{
		throw new Exception("Not implemented");
	}

	Conversion editItem(string id, Conversion fields)
	{
		throw new Exception("Not implemented");
	}

	void updateItem(Conversion item)
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

		new ResourceCrate(config);
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

		new ResourceCrate(config);
	}
	catch (Exception e)
	{
		err = true;
	}

	assert(err, "Expected exception on crate init");

	err = false;
	try
	{
		new ResourceCrate();
	}
	catch (Exception e)
	{
		err = true;
	}

	assert(!err, "Expected exception on crate init");
}
/*
unittest
{
	auto router = new URLRouter();
	auto crate = new ResourceCrate();
	auto crateRouter = new CrateRouter(router, crate);

	request(router)
		.header("Content-Length", "0")
		.header("Content-Type", "multipart/form-data; boundary=----WebKitFormBoundaryePkpFF7tjBAqx29L")
		.post("/resources")
			.send("")
				.end((Response response) => {
					response.writeln;
				});
}
*/
