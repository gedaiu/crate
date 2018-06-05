module crate.collection.memory;

import std.conv;
import std.algorithm;
import std.array;
import std.range;
import std.stdio;
import std.exception;
import std.typecons;

import crate.ctfe;
import crate.base;
import crate.error;

import vibe.data.json;

/// Convert a Json range to a ICrateSelector
class CrateRange : ICrateSelector
{
  private {
    InputRange!Json originalData;
    InputRange!Json data;
  }

  ///
  this(Json[] data) {
    this.originalData = inputRangeObject(data);
    this.data = inputRangeObject(data);
  }

  ///
  this(T)(T data) {
    this.originalData = data.inputRangeObject;
    this.data = data.inputRangeObject;
  }

  override @trusted {

    /// March an item if exactly one field value
    ICrateSelector where(string field, string value) @trusted {
      data = data
        .map!(a => tuple(a, a.flatten))
        .filter!(a => field in a[1])
        .filter!(a => a[1][field].to!string == value)
        .map!(a => a[0])
          .inputRangeObject;

      return this;
    }

    /// ditto
    ICrateSelector where(string field, bool value) {
      data = data
        .map!(a => tuple(a, a.flatten))
        .filter!(a => field in a[1])
        .filter!(a => a[1][field].to!bool == value)
        .map!(a => a[0])
          .inputRangeObject;

      return this;
    }
    
    /// Match an item if a filed value contains at least one value from the values list
    ICrateSelector whereAny(string field, string[] values) @safe {
      data = data
        .map!(a => tuple(a, a.flatten))
        .filter!(a => field in a[1])
        .filter!(a => values.canFind(a[1][field].to!string))
        .map!(a => a[0])
          .inputRangeObject;

      return this;
    }
    //ditto
    ICrateSelector whereAny(string field, ObjectId[] ids) {
      return whereAny(field, ids.map!(a => a.toString).array);
    }

    /// Match an item if the array field contains at least one value from the values list
    ICrateSelector whereArrayAny(string arrayField, string[] values) {
      return whereAny(arrayField, values);
    }

    /// ditto
    ICrateSelector whereArrayAny(string arrayField, ObjectId[] ids) {
      return whereAny(arrayField, ids);
    }

    /// Match an item if the array field contains the `value` element
    ICrateSelector whereArrayContains(string field, string value) {
      data = data.filter!(a => (cast(Json[])a[field]).canFind(Json(value))).inputRangeObject;
      return this;
    }

    /// Match an item if an array field contains an object that has the field equals with the value
    ICrateSelector whereArrayFieldContains(string arrayField, string field, string value) {
      data = data
              .filter!(a => (cast(Json[])a[arrayField])
                .map!(a => a[field])
                .canFind(Json(value)))
                .inputRangeObject;

      return this;
    }

    /// Match an item using a substring
    ICrateSelector like(string field, string value) {
      data = data
        .map!(a => tuple(a, a.flatten))
        .filter!(a => field in a[1])
        .filter!(a => a[1][field].to!string.canFind(value))
        .map!(a => a[0])
          .inputRangeObject;

      return this;
    }

    /// Perform an or logical operation 
    ICrateSelector or() {
      assert(false);
    }

    /// Perform an and logical operation 
    ICrateSelector and() {
      assert(false);
    }

    /// Limit the number of results
    ICrateSelector limit(size_t nr) {
      data = data.take(nr).inputRangeObject;
      return this;
    }

    /// Execute the selector and return a range of JSONs
    InputRange!Json exec() @trusted {
      return data;
    }
  }
}

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
