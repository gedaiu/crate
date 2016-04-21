module crate.openapi;

import vibe.http.router;
import crate.base;
import std.stdio;

string toOpenApi(T)(CrateRouter!T router)
{
	throw new Exception("not implemented");
}


version (unittest)
{
	import crate.request;
	import crate.router;
	import vibe.data.serialization;
	import vibe.data.json;

	bool isTestActionCalled;

	struct TestModel
	{
		@optional {
			string _id;
			string other = "";
		}

		string name = "";

		void action() {
			isTestActionCalled = true;
		}

		string actionResponse() {
			isTestActionCalled = true;
			return "ok.";
		}
	}

	class TestCrate : Crate!TestModel {
		TestModel item;

		TestModel[] getList() {
			return [ item ];
		}

		TestModel addItem(TestModel item) {
			throw new Exception("addItem not implemented");
		}

		TestModel getItem(string id) {
			return item;
		}

		TestModel editItem(string id, Json fields) {
			item.name = fields.name.to!string;

			return item;
		}

		void deleteItem(string id) {
			throw new Exception("deleteItem not implemented");
		}
	}
}

unittest
{
	auto router = new URLRouter();
	auto crate = new TestCrate;

	auto crateRouter = new CrateRouter!TestModel(router, crate);

	auto description = crateRouter.toOpenApi;

	description.writeln;
}
