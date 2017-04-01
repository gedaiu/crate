module crate.datatransformer.apiuser;

import std.algorithm;
import std.array;
import std.stdio;
import std.conv;

import vibe.inet.url;
import vibe.http.router;
import vibe.http.form;
import vibe.data.json;

import vibeauth.users;

import crate.collection.memory;
import crate.base;
import crate.collection.proxy;


private {
	Json fromCrate(const Json data) {
		Json result = Json.emptyObject;

		result["_id"] = data["_id"];
		result["name"] = data["name"];
		result["username"] = data["username"];
		result["email"] = data["email"];

		return result;
	}

	UserData toCrate(const User data) {
		return UserData();
	}
}


struct User {
	string _id;

	string name;
	string username;
	string email;
}

class ApiUserSelector: ProxySelector {

	this(ICrateSelector selector) {
		super(selector);
	}

	override
	Json[] exec() {
		"exec!".writeln;
		return super.exec.map!(a => a.fromCrate).array;
	}
}

class ApiUserTransformer: Crate!User {

	private Crate!UserData crate;

	this(Crate!UserData crate) {
		this.crate = crate;
	}

	CrateConfig!User config() {
		CrateConfig!User config;

		config.getList = crate.config.getList;
		config.getItem = crate.config.getItem;
		config.addItem = crate.config.addItem;
		config.deleteItem = crate.config.deleteItem;
		config.replaceItem = crate.config.replaceItem;
		config.updateItem = crate.config.updateItem;
		config.singular = crate.config.singular;
		config.plural = crate.config.plural;

		return config;
	}

	ICrateSelector get() {
		return new ApiUserSelector(crate.get());
	}

	Json[] getList() {
		return crate.getList().map!(a => a.fromCrate).array;
	}

	Json addItem(Json item) {
		return crate.addItem(item);
	}

	Json getItem(string id) {
		return crate.getItem(id).fromCrate;
	}

	void updateItem(Json item) {
		crate.updateItem(item);
	}

	void deleteItem(string id) {
		crate.deleteItem(id);
	}
}


@("The user data transformer should hide the sensible fields on GET")
unittest
{
	import http.request;
	import http.json;
	import bdd.base;
	import crate.http.router;
	import crate.policy.restapi;
	import crate.base;
	import std.stdio;

	CrateConfig!UserData config;
	config.singular = "user";
	config.plural = "users";

	auto router = new URLRouter();
	auto userCrate = new ApiUserTransformer(new MemoryCrate!UserData(config));

	router
		.crateSetup
			.add(userCrate);

	auto userJson = `{
		"_id": 1,
		"email": "test2@asd.asd",
		"name": "test",
		"username": "test_user",
		"isActive": true,
		"password": "password",
		"salt": "salt",
		"scopes": ["scopes"],
		"tokens": [{ "name": "token2", "expire": "2100-01-01T00:00:00", "type": "Bearer", "scopes": [] }],
	}`;

	userCrate.addItem(userJson.parseJsonString);

	request(router)
		.get("/users")
			.expectStatusCode(200)
			.end((Response response) => {
				response.bodyJson["users"].length.should.be.graterThan(0);

				auto user = response.bodyJson["users"][0];
				user.keys.should.contain(["_id", "email", "name", "username"]);
				user.keys.should.not.contain(["isActive", "password", "salt", "scopes", "tokens"]);
				user["_id"].to!string.should.equal("1");
				user["email"].to!string.should.equal("test2@asd.asd");
				user["name"].to!string.should.equal("test");
				user["username"].to!string.should.equal("test_user");
			});

	request(router)
		.get("/users/1")
			.expectStatusCode(200)
			.end((Response response) => {
				auto user = response.bodyJson["user"];
				user.keys.should.contain(["_id", "email", "name", "username"]);
				user.keys.should.not.contain(["isActive", "password", "salt", "scopes", "tokens"]);

				user["_id"].to!string.should.equal("1");
				user["email"].to!string.should.equal("test2@asd.asd");
				user["name"].to!string.should.equal("test");
				user["username"].to!string.should.equal("test_user");
			});
}
