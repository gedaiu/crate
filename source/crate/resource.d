module crate.resource;

public import vibe.core.stream;

import vibe.data.json;
public import vibe.inet.webform;

import std.conv;
import std.file;
import std.stdio;

interface CrateResource {
	string contentType();
	void write(OutputStream bodyWriter);
	void read(const FilePart file);
	ulong size();
}

version(unittest) {
	import crate.request;

	class TestResource : CrateResource {
		static string lastRead;

		string contentType() {
			return "test/resource";
		}

		void write(OutputStream bodyWriter) {
			bodyWriter.write("test body".to!(char[]));
		}

		void read(const FilePart file) {
			lastRead = readText(file.tempPath.toString);

			lastRead.writeln;
		}

		ulong size() {
			return "test body".length;
		}

		override string toString() const {
			return "test resource";
		}

		static TestResource fromString(string src) {
			return new TestResource;
		}
	}

	struct ResourceModel
	{
		string _id = "1";
		string name = "test";
		TestResource resource = new TestResource;
	}
}

@("Access a model with resources")
unittest {
	import vibe.http.router;
	import crate.policy.restapi;
	import crate.http.router;
	import std.stdio;

	auto router = new URLRouter();
	auto resourceCrate = new TestCrate!ResourceModel;

	router
		.crateSetup
			.add(resourceCrate)
			.enableResource!(ResourceModel, "resource");

	request(router)
		.get("/resourcemodels/1")
			.expectStatusCode(200)
			.end((Response response) => {
				response.bodyString.writeln;
				assert(response.bodyJson["resourceModel"]["resource"] == "test resource");
			});

	request(router)
		.get("/resourcemodels/1/resource")
			.expectStatusCode(200)
			.expectHeader("Content-Type", "test/resource")
			.end((Response response) => {
				assert(response.bodyString == "test body");
			});


	string data = "-----------------------------9855312492823326321373169801\r\n";
	data ~= "Content-Disposition: form-data; name=\"resource\"; filename=\"resource.txt\"\r\n";
	data ~= "Content-Type: text/plain\r\n\r\n";
	data ~= "hello\r\n";
	data ~= "-----------------------------9855312492823326321373169801--\r\n";

	request(router)
		.header("Content-Type", "multipart/form-data; boundary=---------------------------9855312492823326321373169801")
		.post("/resourcemodels/1/resource")
		.expectStatusCode(201)
		.send(data)
		.end((Response response) => {
			assert(TestResource.lastRead == "hello");
		});
}
