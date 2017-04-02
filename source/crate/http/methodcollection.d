module crate.http.methodcollection;

import vibe.inet.url;
import vibe.http.router;
import vibe.data.json;

import crate.base;
import crate.error;
import crate.collection.proxy;
import crate.collection.idremover;
import crate.collection.idcreator;
import crate.http.headers;

import std.conv;
import std.exception;
import std.stdio;
import std.json;
import std.algorithm;
import std.array;

class MethodCollection(Type)
{
	private
	{
		immutable CrateConfig!Type config;
		CrateCollection collection;
		const CratePolicy policy;
	}

	this(const CratePolicy policy, CrateCollection collection, CrateConfig!Type config)
	{
		this.policy = policy;
		this.collection = collection;
		this.config = config;
	}

	private Json requestJson(HTTPServerRequest request) {
		Json data = request.json;

		if(data.type == Json.Type.undefined) {
			data = Json.emptyObject;

			foreach(key; request.form) {
				data[key] = request.form[key];
			}
		}

		return data;
	}

	void optionsItem(HTTPServerRequest request, HTTPServerResponse response)
	{
		auto crate = collection.getByPath(request.path);
		addItemCORS(response);

		crate.getItem(request.params["id"]);
		response.writeBody("", 200);
	}

	void optionsList(HTTPServerRequest, HTTPServerResponse response)
	{
		addListCORS(response);
		response.writeBody("", 200);
	}

	void getItem(HTTPServerRequest request, HTTPServerResponse response)
	{
		auto crate = collection.getByPath(request.path);
		addItemCORS(response);
		auto data = crate.getItem(request.params["id"]);

		FieldDefinition definition = crate.definition;
		auto denormalised = policy.serializer.denormalise(data, definition);

		response.writeJsonBody(denormalised, 200, policy.mime);
	}

	void updateItem(HTTPServerRequest request, HTTPServerResponse response)
	{
		auto crate = collection.getByPath(request.path);
		addItemCORS(response);

		FieldDefinition definition = crate.definition;
		auto item = crate.getItem(request.params["id"]);

		auto newData = policy.serializer.normalise(request.params["id"], requestJson(request), definition);
		auto mixedData = mix(item, newData);
		checkRelationships(mixedData, definition);

		crate.updateItem(mixedData);

		auto data = policy.serializer.denormalise(mixedData, definition);
		response.writeJsonBody(data, 200, policy.mime);
	}

	void replaceItem(HTTPServerRequest request, HTTPServerResponse response)
	{
		auto crate = collection.getByPath(request.path);
		addItemCORS(response);

		FieldDefinition definition = crate.definition;
		auto item = crate.getItem(request.params["id"]);

		auto newData = policy.serializer.normalise(request.params["id"], requestJson(request), definition);

		checkRelationships(newData, definition);
		checkFields(newData, definition);
		crate.updateItem(newData);

		response.writeJsonBody(policy.serializer.denormalise(newData,
				definition), 200, policy.mime);
	}

	void deleteItem(HTTPServerRequest request, HTTPServerResponse response)
	{
		auto crate = collection.getByPath(request.path);
		addItemCORS(response);

		crate.deleteItem(request.params["id"]);
		response.writeBody("", 204, policy.mime);
	}

	void getList(HTTPServerRequest request, HTTPServerResponse response)
	{
		auto crate = collection.getByPath(request.path);

		addListCORS(response);

		FieldDefinition definition = crate.definition;

		string[string] parameters;

		auto data = policy.serializer.denormalise(crate.getList(parameters), definition);
		response.writeJsonBody(data, 200, policy.mime);
	}

	void postItem(HTTPServerRequest request, HTTPServerResponse response)
	{
		auto crate = collection.getByPath(request.path);
		addListCORS(response);

		FieldDefinition definition = crate.definition;
		auto data = policy.serializer.normalise("", requestJson(request), definition);
		checkRelationships(data, definition);
		checkFields(data, definition);

		try {
			data = ItemIdCreator(data, definition).toJson;
			data = ItemIdRemover(data.deserializeJson!Type.serializeToJson, definition).toJson;
		} catch (JSONException e) {
			debug writeln(e);
			throw new CrateValidationException(e.msg, e);
		}

		crate.addItem(data);

		Json item = policy.serializer.denormalise(data, definition);
		response.headers["Location"] = (request.fullURL ~ Path(data["_id"].to!string)).to!string;
		response.writeJsonBody(item, 201, policy.mime);
	}

	private
	{
		void addListCORS(HTTPServerResponse response)
		{
			string[] methods = [ "OPTIONS" ];

			if (config.getList)
			{
				methods ~= "GET";
			}

			if (config.addItem)
			{
				methods ~= "POST";
			}

			response.addHeaderValues("Access-Control-Allow-Origin", [ "*" ]);
			response.addHeaderValues("Access-Control-Allow-Methods", methods);
			response.addHeaderValues("Access-Control-Allow-Headers", [ "Content-Type" ]);
		}

		void addItemCORS(HTTPServerResponse response)
		{
			string[] methods = [ "OPTIONS" ];

			if (config.getList)
			{
				methods ~= "GET";
			}

			if (config.updateItem)
			{
				methods ~= "PATCH";
			}

			if (config.replaceItem)
			{
				methods ~= "PUT";
			}

			if (config.deleteItem)
			{
				methods ~= "DELETE";
			}

			response.addHeaderValues("Access-Control-Allow-Origin", [ "*" ]);
			response.addHeaderValues("Access-Control-Allow-Methods", methods);
			response.addHeaderValues("Access-Control-Allow-Headers", [ "Content-Type" ]);
		}

		void checkFields(Json data, FieldDefinition definition)
		{
			foreach (field; definition.fields)
			{
				bool canCheck = !field.isId && !field.isOptional && field.name != "";
				bool isSet = data[field.name].type !is Json.Type.undefined;

				enforce!CrateValidationException(!canCheck || isSet,
						"`" ~ field.name ~ "` is required.");
			}
		}

		void checkRelationships(ref Json data, FieldDefinition definition)
		{
			foreach (field; definition.fields)
			{
				if(!field.isOptional && field.name != "" && data[field.name].type == Json.Type.undefined) {
					throw new CrateValidationException("`" ~ field.name ~ "` is missing");
				}

				if(field.isOptional && data[field.name].type == Json.Type.undefined) {
					continue;
				}

				if (field.isRelation)
				{
					auto crate = collection.getByType(field.type);

					if (field.isArray)
					{
						enforce!CrateValidationException(data[field.name].type == Json.Type.array,
							"`" ~ field.name ~ "` should be an array.");

						try
						{
							data[field.name] = Json((cast(Json[])data[field.name]).map!((ref id) => crate.getItem(id.to!string)).array);
						}
						catch (CrateNotFoundException e)
						{
							throw new CrateRelationNotFoundException(
									"Can not resove array", e);
						}
					}
					else
					{
						string id = data[field.name].to!string;

						try
						{
							data[field.name] = crate.getItem(id);
						}
						catch (CrateNotFoundException e)
						{
							throw new CrateRelationNotFoundException(
									"Item `" ~ field.type ~ "` in field `"
									~ field.name ~ "` with id `" ~ id ~ "` not found");
						}
					}
				}
			}
		}
	}
}

Json mix(Json data, Json newData)
{
	Json mixedData = data;

	foreach (string key, value; newData)
	{
		if (mixedData[key].type == Json.Type.object)
		{
			mixedData[key] = mix(mixedData[key], value);
		}
		else
		{
			mixedData[key] = value;
		}
	}

	return mixedData;
}

@("check the json mixer with simple values")
unittest
{
	Json data = Json.emptyObject;
	Json newData = Json.emptyObject;

	data["key1"] = 1;
	newData["key2"] = 2;

	auto result = data.mix(newData);
	assert(result["key1"].to!int == 1);
	assert(result["key2"].to!int == 2);
}

@("check the json mixer with nested values")
unittest
{
	Json data = Json.emptyObject;
	Json newData = Json.emptyObject;

	data["key"] = Json.emptyObject;
	data["key"]["nested1"] = 1;

	newData["key"] = Json.emptyObject;
	newData["key"]["nested2"] = 2;

	auto result = data.mix(newData);
	assert(result["key"]["nested1"].to!int == 1);
	assert(result["key"]["nested2"].to!int == 2);
}
