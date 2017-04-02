module crate.collection.proxy;

import crate.base;
import crate.ctfe;
import vibe.data.json;

import std.traits;
import std.stdio, std.string;

class CrateProxy: Crate!void
{

	private
	{
		CrateConfig!void configProxy;

		ICrateSelector delegate() getRef;
		Json[]delegate(string[string]) getListRef;
		Json delegate(Json) addItemRef;
		Json delegate(string) getItemRef;
		void delegate(Json) updateItemRef;
		void delegate(string) deleteItemRef;

		FieldDefinition _definition;
	}

	this(T)(ref Crate!T crate)
	{
		set(crate.config);

		getRef = &crate.get;
		getListRef = &crate.getList;
		addItemRef = &crate.addItem;
		getItemRef = &crate.getItem;
		updateItemRef = &crate.updateItem;
		deleteItemRef = &crate.deleteItem;

		static if(isAggregateType!T) {
			_definition = getFields!T;
			_definition.singular = crate.config.singular;
			_definition.plural = crate.config.plural;
		} else {
			_definition = FieldDefinition();
		}
	}

	private void set(T)(CrateConfig!T crate) {
		configProxy.getList = crate.getList;
		configProxy.getItem = crate.getItem;
		configProxy.addItem = crate.addItem;
		configProxy.deleteItem = crate.deleteItem;
		configProxy.replaceItem = crate.replaceItem;
		configProxy.updateItem = crate.updateItem;

		configProxy.singular = crate.singular;
		configProxy.plural = crate.plural;
	}

	FieldDefinition definition()
	{
		return _definition;
	}

	CrateConfig!void config()
	{
		return configProxy;
	}

	ICrateSelector get() {
		return getRef();
	}

	Json[] getList(string[string] parameters)
	{
		return getListRef(parameters);
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

class CrateCollection
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

	string[] paths() {
		return crates.keys;
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

class ProxySelector: ICrateSelector {

	protected {
		ICrateSelector selector;
	}

	this(ICrateSelector selector) {
		this.selector = selector;
	}

	override {
		ICrateSelector where(string field, string value) {
			this.selector.where(field, value);

			return this;
		}

		ICrateSelector whereArrayContains(string field, string value) {
			this.selector.whereArrayContains(field, value);

			return this;
		}

		ICrateSelector whereArrayFieldContains(string arrayField, string field, string value) {
			this.selector.whereArrayFieldContains(arrayField, field, value);

			return this;
		}

		ICrateSelector limit(ulong nr) {
			this.selector.limit(nr);

			return this;
		}

		Json[] exec() {
			return this.selector.exec;
		}
	}
}
