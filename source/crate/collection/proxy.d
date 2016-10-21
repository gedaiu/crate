module crate.collection.proxy;

import crate.base;
import crate.ctfe;
import vibe.data.json;

import std.stdio, std.string;

class CrateProxy : Crate!void
{

	private
	{
		CrateConfig delegate() configRef;
		Json[]delegate() getListRef;
		Json delegate(Json item) addItemRef;
		Json delegate(string id) getItemRef;
		void delegate(Json item) updateItemRef;
		void delegate(string id) deleteItemRef;

		FieldDefinition _definition;
	}

	this(T)(ref Crate!T crate)
	{
		configRef = &crate.config;
		getListRef = &crate.getList;
		addItemRef = &crate.addItem;
		getItemRef = &crate.getItem;
		updateItemRef = &crate.updateItem;
		deleteItemRef = &crate.deleteItem;

		_definition = getFields!T;
	}

	FieldDefinition definition()
	{
		return _definition;
	}

	CrateConfig config()
	{
		return configRef();
	}

	Json[] getList()
	{
		return getListRef();
	}

	Json addItem(Json item)
	{
		return addItemRef(item);
	}

	Json getItem(string id)
	{
		return getItemRef(id);
	}

	void updateItem(Json item)
	{
		updateItemRef(item);
	}

	void deleteItem(string id)
	{
		deleteItemRef(id);
	}
}

struct CrateCollection
{

	private
	{
		CrateProxy[string] crates;
		string[string] types;
	}

	void addByPath(T)(string basePath, ref Crate!T crate)
	{
		crates[basePath] = new CrateProxy(crate);
		types[T.stringof] = basePath;
	}

	CrateProxy getByPath(string path)
	{
		foreach (basePath, crate; crates)
		{
			if (path.indexOf(basePath) == 0)
			{
				return crate;
			}
		}

		assert(false, "No crate found found at `" ~ path ~ "`");
	}

	CrateProxy getByType(string type)
	{
		if (type in types)
		{
			return crates[types[type]];
		}

		assert(false, "Crate not found");
	}
}
