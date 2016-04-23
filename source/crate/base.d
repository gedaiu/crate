module crate.base;

import vibe.data.json;

import std.string, std.traits, std.conv;

import swaggerize.definitions;

struct CrateConfig(T)
{
	string singular = T.stringof.toLower;
	string plural = T.stringof.toLower ~ "s";

	bool getList = true;
	bool getItem = true;
	bool addItem = true;
	bool deleteItem = true;
	bool updateItem = true;
}

interface Crate(T)
{
	T[] getList();

	T addItem(T item);
	T getItem(string id);
	T editItem(string id, Json fields);
	void deleteItem(string id);
}

interface CrateSerializer(T)
{
	Json serialize(T item);
	Json serialize(T[] items);

	T deserialize(Json data);

	string mime();
}
