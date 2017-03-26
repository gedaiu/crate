module crate.datatransformer.apiuser;

import vibe.inet.url;
import vibe.http.router;
import vibe.http.form;
import vibe.data.json;

import vibeauth.users;

import crate.collection.memory;
/*
@("The user data transformer should hide the sensible fields")
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
	auto userCrate = new MemoryCrate!UserData(config);

	router
		.crateSetup
			.add(userCrate);
				//.dataTransformer!(UserData, ApiUserTransformer);

	auto userJson = `{
		"_id": 1,
		"email": "test2@asd.asd",
		"name": "test",
		"username": "test",
		"isActive": true,
		"password": "password",
		"salt": "salt",
		"scopes": ["scopes"],
		"tokens": [{ "name": "token2", "expire": "2100-01-01T00:00:00", "type": "Bearer", "scopes": [] }],
	}`;

	userCrate.addItem(userJson.parseJsonString);

	request(router)
		.get("/userdatas")
			.expectStatusCode(200)
			.end((Response response) => {
				writeln("users", response.bodyJson.toPrettyString);
				response.bodyJson["users"].length.should.be.graterThan(0);
				//response.bodyJson["users"].keys.contain(["_id", "email", "name", "username"]);
				//response.bodyJson["users"].keys.not.contain(["isActive", "password", "salt", "scopes", "tokens"]);
			});
}
*/
