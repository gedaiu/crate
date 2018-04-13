module crate.collection.memory;

import std.conv;
import std.algorithm;
import std.array;
import std.range;
import std.stdio;
import std.exception;

import crate.ctfe;
import crate.base;
import crate.error;

import vibe.data.json;

class MemoryCrate(T) : Crate!T
{
  protected {
    ulong lastId;
    Json[] list;
    CrateConfig!T _config;
    enum string idField = getFields!T.idField.name;
  }

  this(CrateConfig!T config = CrateConfig!T())
  {
    this._config = config;
  }

  @trusted:
    CrateConfig!T config() {
      return _config;
    }

    ICrateSelector get() {
      return new CrateRange(list);
    }

    ICrateSelector getList()
    {
      return get();
    }

    Json addItem(Json item)
    {
      lastId++;
      item[idField] = lastId.to!string;
      list ~= item;

      return item;
    }

    ICrateSelector getItem(string id)
    {
      return get.where(idField, id).limit(1);
    }

    Json updateItem(Json item)
    {
      auto match = list.enumerate
        .filter!(a => a[1][idField] == item[idField]);

      enforce!CrateNotFoundException(!match.empty, "No item found.");

      list[match.front[0]] = item;

      return item;
    }

    void deleteItem(string id)
    {
      auto match = list
        .filter!(a => a[idField] == id);

      enforce!CrateNotFoundException(!match.empty, "No item found.");

      list = list.filter!(a => a[idField].to!string != id).array;
    }
}
