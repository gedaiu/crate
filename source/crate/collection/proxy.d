module crate.collection.proxy;

import crate.base;
import crate.ctfe;
import vibe.data.json;

import std.traits;
import std.stdio, std.string;
import std.range.interfaces;

class CrateProxy: Crate!void
{

  private
  {
    CrateConfig!void configProxy;

    ICrateSelector delegate() getRef;
    ICrateSelector delegate() getListRef;
    Json delegate(Json) addItemRef;
    ICrateSelector delegate(string) getItemRef;
    Json delegate(Json) updateItemRef;
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

  @trusted:
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

    ICrateSelector getList()
    {
      return getListRef();
    }

    Json addItem(Json item)
    {
      return addItemRef(item);
    }

    ICrateSelector getItem(string id)
    {
      return getItemRef(id);
    }

    Json updateItem(Json item)
    {
      return updateItemRef(item);
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

  this(ICrateSelector selector) @safe {
    this.selector = selector;
  }

  override @safe {
    ICrateSelector where(string field, string value) {
      return new ProxySelector(this.selector.where(field, value));
    }

    ICrateSelector whereArrayContains(string field, string value) {
      return new ProxySelector(this.selector.whereArrayContains(field, value));
    }

    ICrateSelector whereArrayFieldContains(string arrayField, string field, string value) {
      return new ProxySelector(this.selector.whereArrayFieldContains(arrayField, field, value));
    }

    ICrateSelector limit(size_t nr) {
      return new ProxySelector(this.selector.limit(nr));
    }

    ICrateSelector like(string field, string value) {
      return new ProxySelector(this.selector.like(field, value));
    }

    InputRange!Json exec() {
      return this.selector.exec;
    }
  }
}
