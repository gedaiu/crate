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
  private {
    ulong lastId;
		Json[] list;
		CrateConfig _config;
		enum string idField = getFields!T.idField.name;
	}

	this(CrateConfig config = CrateConfig())
	{
		this._config = config;
	}

	CrateConfig config() {
		return _config;
	}

  Json[] get(string field, string value, ulong limit) {
    return list.filter!(a => a[field] == value).take(limit).array;
  }

  Json[] getList()
  {
    return list;
  }

  Json addItem(Json item)
  {
    lastId++;
    item["_id"] = lastId.to!string;
    list ~= item;

    return item;
  }

  Json getItem(string id)
  {
    auto result = get("_id", id, 1);

    enforce!CrateNotFoundException(result.length > 0, "No item found.");

    return result[0];
  }

  void updateItem(Json item)
  {
    auto match = list.enumerate
      .filter!(a => a[1][idField] == item[idField]);

    enforce!CrateNotFoundException(!match.empty, "No item found.");

    list[match.front[0]] = item;
  }

  void deleteItem(string id)
  {
    list = list.filter!(a => a[idField].to!string == id).array;
  }
}