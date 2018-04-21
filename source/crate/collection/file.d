module crate.collection.file;

import std.range;
import std.traits;
import std.conv;
import std.stdio;
import std.string;
import std.file;
import std.path;
import std.base64;
import std.algorithm;
import std.uuid;
import std.path;
import std.exception;
import vibe.inet.webform;

import crate.mime;
import crate.resource;

class CrateFile : CrateResource {
	private string currentFileName;
	public static string defaultPath = "files/";

	this() {}

	this(string name) @safe {
		currentFileName = name;
	}

	void read(const FilePart file) {
		currentFileName.remove;

		auto ext = file.headers["Content-Type"].to!string.toExtension;
		auto name = randomUUID.to!string.replace("-", "");

		currentFileName = chainPath(defaultPath, name.to!string).to!string ~ ext;

		file.tempPath.toString.copy(currentFileName);
	}

	override string toString() const @safe {
		return currentFileName;
	}

	static CrateFile fromString(string encoded) @trusted {
		enum dataLength = "data:".length;

		if(encoded.length > dataLength && encoded[0..dataLength] == "data:") {
			return CrateFile.fromBase64(encoded);
		}

		return new CrateFile(encoded);
	}

	static CrateFile fromBase64(Range)(Range r) @trusted if (isInputRange!(Unqual!Range)) {
		return fromBase64(randomUUID.to!string.replace("-", ""), r);
	}

	static CrateFile fromBase64(Range)(string name, Range r) @trusted if (isInputRange!(Unqual!Range)) {
		return fromBase64(defaultPath, name, r);
	}

	static CrateFile fromBase64(Range)(string path, string name, Range r) @trusted if (isInputRange!(Unqual!Range)) {
		enum dataLength = "data:".length;
		enum base64Length = ";base64,".length;

		enforce!Exception(r[0..dataLength] == "data:", "Invalid file format. Expected `data:[mime];base64,[content]`");

		if(!path.exists) {
			path.mkdirRecurse;
		}

		auto contentStart = r.indexOf(";base64,");

		const string mime = r[dataLength..contentStart];
		string filePath = chainPath(path, name).to!string ~ mime.toExtension;

		auto f = File(filePath, "w");
		scope(exit) f.close;

		foreach(decoded; Base64.decoder(r[contentStart + base64Length ..$].map!(a => cast(char) a))) {
			f.write(cast(char) decoded);
		}

		return new CrateFile(filePath);
	}

	string contentType() {
		return currentFileName.extension.toMime;
	}

	void write(BodyOutputStream bodyWriter) {
		auto f = File(currentFileName, "r");
		scope(exit) f.close;

		foreach (ubyte[] buffer; f.chunks(512))
		{
			bodyWriter.write(buffer);
		}
	}

	bool hasSize() {
		return true;
	}

	ulong size() {
		return currentFileName.getSize;
	}
}

version (unittest)
{
	import crate.base;
	import fluentasserts.vibe.request;
	import fluent.asserts;
	import crate.http.router;
	import crate.collection.memory;

	import vibe.data.json;
	import vibe.data.bson;
	import vibe.http.router;

	struct Item {
		string _id = "item_id";
		Child child;
		CrateFile file = new CrateFile;
	}

	struct Child
	{
		CrateFile file = new CrateFile;
	}
}

@("the user should be able to upload a file as a base64 data")
unittest {
	import crate.policy.restapi;
	import std.stdio;

	auto router = new URLRouter();
	auto baseCrate = new MemoryCrate!Item;

	router
		.crateSetup
			.add(baseCrate)
				.enableResource!(Item, "/file")(baseCrate)
				.enableResource!(Item, "/child/file")(baseCrate);

	Json data = `{
		"item": {
			"file": "data:text/plain;base64,dGhpcyBpcyBhIHRleHQgZmlsZQ==",
			"child": {
				"file": "data:text/plain;base64,aGVsbG8gd29ybGQ="
			}
		}
	}`.parseJsonString;

	scope(exit) "files/".rmdirRecurse;

	request(router)
		.post("/items")
			.send(data)
				.expectStatusCode(201)
				.end((Response response) => {
					string parentFile = response.bodyJson["item"]["file"].to!string;
					string childFile = response.bodyJson["item"]["child"]["file"].to!string;

					assert(parentFile.indexOf(".txt") != -1, "Invalid filename");
					assert(childFile.indexOf(".txt") != -1, "Invalid filename inside relation");

					assert(exists(parentFile), "The parent file was not created");
					assert(exists(childFile), "The child file was not created");

					assert(readText(parentFile) == "this is a text file", "The parent file contains invalid data");
					assert(readText(childFile) == "hello world" , "The child file contains invalid data");
				});

	data = `{
		"item": {
			"file": "data:text/plain;base64,Y2hhbmdlMQ==",
			"child": {
				"file": "data:text/plain;base64,Y2hhbmdlMg=="
			}
		}
	}`.parseJsonString;

	request(router)
		.put("/items/1")
			.send(data)
				.expectStatusCode(200)
				.end((Response response) => {
					response.bodyJson["item"]["file"].to!string.should.not.startWith("data:");
				});
}

@("the user should be able to download a file")
unittest {
	import crate.policy.restapi;
	import std.stdio;

	"files".mkdirRecurse;

	auto f = File("files/item.txt", "w");
	f.write("this is the item");
	f.close;

	f = File("files/child.txt", "w");
	f.write("this is the child");
	f.close;

	scope(exit) "files/".rmdirRecurse;

	auto baseCrate = new MemoryCrate!Item;
	auto item = Item();

	item.file = new CrateFile("files/item.txt");
	item.child.file = new CrateFile("files/child.txt");

	auto jsonItem = item.serializeToJson;
	baseCrate.addItem(jsonItem);

	auto router = new URLRouter();

	router
		.crateSetup
			.add(baseCrate)
				.enableResource!(Item, "/file")(baseCrate)
				.enableResource!(Item, "/child/file")(baseCrate);

	request(router)
		.get("/items/1/file")
			.expectStatusCode(200)
			.end((Response response) => {
				response.bodyString.should.equal("this is the item");
			});

	request(router)
		.get("/items/1/child/file")
			.expectStatusCode(200)
			.end((Response response) => {
				response.bodyString.should.equal("this is the child");
			});

	string data = "-----------------------------9855312492823326321373169801\r\n";
	data ~= "Content-Disposition: form-data; name=\"file\"; filename=\"resource.txt\"\r\n";
	data ~= "Content-Type: text/plain\r\n\r\n";
	data ~= "new file\r\n";
	data ~= "-----------------------------9855312492823326321373169801--\r\n";

	request(router)
		.header("Content-Type", "multipart/form-data; boundary=---------------------------9855312492823326321373169801")
		.post("/items/1/file")
			.send(data)
			.expectStatusCode(201)
			.end((Response response) => { });

	request(router)
		.get("/items/1/file")
			.expectStatusCode(200)
			.end((Response response) => {
				assert(response.bodyString == "new file");
			});
}
