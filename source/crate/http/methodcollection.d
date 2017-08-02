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
		ICrateFilter[] filters;
	}

	this(const CratePolicy policy, CrateCollection collection, CrateConfig!Type config, ICrateFilter[] filters)
	{
		this.policy = policy;
		this.collection = collection;
		this.config = config;
		this.filters = filters.dup;
	}

	private Json requestJson(HTTPServerRequest request) {
		Json data = request.json;

		if(data.type == Json.Type.undefined) {
			data = Json.emptyObject;

			foreach(item; request.form.byKeyValue) {
				data[item.key] = item.value;
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

		foreach(filter; filters) {
			data = filter.apply(request, data);
		}

		auto item = data.exec;

		if(item.empty) {
			throw new CrateNotFoundException("The resource can not be found.");
		}

		FieldDefinition definition = crate.definition;
		auto denormalised = policy.serializer.denormalise(item.front, definition);
		response.writeJsonBody(denormalised, 200, policy.mime);
	}

	void updateItem(HTTPServerRequest request, HTTPServerResponse response)
	{
		auto crate = collection.getByPath(request.path);
		addItemCORS(response);

		FieldDefinition definition = crate.definition;
		auto data = crate.getItem(request.params["id"]);

		foreach(filter; filters) {
			data = filter.apply(request, data);
		}

		auto crateRange = data.exec;

		if(crateRange.empty) {
			throw new CrateNotFoundException("Can not find the resource.");
		}

		auto item = crateRange.front;

		auto newData = policy.serializer.normalise(request.params["id"], requestJson(request), definition);
		auto mixedData = mix(item, newData);
		checkRelationships(mixedData, definition);

		crate.updateItem(mixedData);

		auto serializedItem = policy.serializer.denormalise(mixedData, definition);
		response.writeJsonBody(serializedItem, 200, policy.mime);
	}

	void replaceItem(HTTPServerRequest request, HTTPServerResponse response)
	{
		auto crate = collection.getByPath(request.path);
		addItemCORS(response);

		FieldDefinition definition = crate.definition;
		auto data = crate.getItem(request.params["id"]);

		foreach(filter; filters) {
			data = filter.apply(request, data);
		}

		if(data.exec.empty) {
			throw new CrateNotFoundException("Can not find the resource.");
		}

		auto newData = policy.serializer.normalise(request.params["id"], requestJson(request), definition);

		checkRelationships(newData, definition);
		checkFields(newData, definition);

		try {
			newData = newData.deserializeJson!Type.serializeToJson.serializeToJson;
		} catch (JSONException e) {
			debug writeln(e);
			throw new CrateValidationException(e.msg, e);
		}

		crate.updateItem(newData);

		response.writeJsonBody(policy.serializer.denormalise(newData,
				definition), 200, policy.mime);
	}

	void deleteItem(HTTPServerRequest request, HTTPServerResponse response)
	{
		auto crate = collection.getByPath(request.path);
		addItemCORS(response);

		auto data = crate.getItem(request.params["id"]);

		foreach(filter; filters) {
			data = filter.apply(request, data);
		}

		auto item = data.exec;

		if(item.empty) {
			throw new CrateNotFoundException("The resource can not be found.");
		}

		crate.deleteItem(request.params["id"]);
		response.writeBody("", 204, policy.mime);
	}

	void getList(HTTPServerRequest request, HTTPServerResponse response)
	{
		auto crate = collection.getByPath(request.path);

		addListCORS(response);

		FieldDefinition definition = crate.definition;

		string[string] parameters;

		foreach(string key, value; request.query) {
			parameters[key] = value;
		}

		auto list = crate.getList(parameters);

		foreach(filter; filters) {
			list = filter.apply(request, list);
		}

		auto data = policy.serializer.denormalise(list.exec, definition);
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
							auto relations = (cast(Json[])data[field.name]).map!((ref id) => crate.getItem(id.to!string).exec.front).array;
							data[field.name] = relations;
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
							data[field.name] = crate.getItem(id).exec.front;
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
