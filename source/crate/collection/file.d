module crate.collection.file;

import std.range;
import std.traits;
import std.conv;
import std.stdio;
import std.string;


struct CrateFile {
	private string currentFileName;

	this(string name) {
		currentFileName = name;
	}

	string toString() const {
		return currentFileName;
	}

	static CrateFile fromString(string encoded) {
		return CrateFile.fromBase64("file.txt", encoded);
	}

	static CrateFile fromBase64(Range)(string name, Range r) if (isInputRange!(Unqual!Range)) {
		return CrateFile(name);
	}
}

version (unittest)
{
	import crate.base;
	import crate.request;
	import crate.http.router;

	import vibe.data.json;
	import vibe.data.bson;
	import vibe.http.router;

	class TestCrate(T) : Crate!T
	{
		Item item;

		CrateConfig config()
		{
			return CrateConfig();
		}

		Json[] getList()
		{
			return [item.serializeToJson];
		}

		Json addItem(Json item)
		{
			item["_id"] = "item_id";
			item["child"]["_id"] = "child_id";

			return item;
		}

		Json getItem(string)
		{
			return item.serializeToJson;
		}

		void updateItem(Json item)
		{
		}

		void deleteItem(string id)
		{
		}
	}

	struct Item {
		string _id = "item_id";
		Child child;
		CrateFile file;
	}

	struct Child
	{
		string _id = "child_id";
		CrateFile file;
	}
}


@("the user should be able to upload a file as a base64 data")
unittest {
	import crate.policy.restapi;
	import std.stdio;

	auto router = new URLRouter();
	auto baseCrate = new TestCrate!Item;
	auto relatedCrate = new TestCrate!Child;

	router
		.crateSetup
			.add(baseCrate)
			.add(relatedCrate);

	Json data = `{
		"item": {
			"file": "data:text/plain;base64,dGhpcyBpcyBhIHRleHQgZmlsZQ==",
			"child": {
				"file": "data:text/plain;base64,aGVsbG8gd29ybGQ="
			}
		}
	}`.parseJsonString;

	request(router)
		.post("/items")
			.send(data)
				.expectStatusCode(201)
				.end((Response response) => {
					response.bodyJson.toPrettyString.writeln;

					assert(response.bodyJson["item"]["file"].to!string.indexOf(".txt") != -1);
					assert(response.bodyJson["item"]["child"]["file"].to!string.indexOf(".txt") != -1);
				});
}
