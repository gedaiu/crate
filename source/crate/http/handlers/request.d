module crate.http.handlers.request;

import std.array;
import std.range;
import std.algorithm;
import std.traits;
import std.exception;
import std.conv ;

import vibe.data.json;
import vibe.stream.operations;
import vibe.http.router;
import crate.base;
import crate.error;
import crate.ctfe;


/// Interface for wrapper crate selelctors
interface IFiltersWrapper {
  ///
  alias GetItemDelegate = ICrateSelector delegate(string id) @safe;

  ///
  void getItem(GetItemDelegate value);

  ///
  VibeHandler handler(VibeHandler next) @safe;
}
/// Wraps a vibe handlers with filter middlewares. See `ICrateFilter`
class FiltersWrapper(Types...) : IFiltersWrapper {

  private {
    Types middlewares;
    GetItemDelegate _getItem;
  }

  /// The list of middlewares
  this(Types middlewares) {
    this.middlewares = middlewares;
  }

  /// Set the get item function
  void getItem(IFiltersWrapper.GetItemDelegate value) {
    this._getItem = value;
  }

  /// Handler used to validate the request against the provided filters
  VibeHandler handler(VibeHandler next) @safe {

    auto localHandler(HTTPServerRequest request, HTTPServerResponse response) @trusted {
      auto result = _getItem(request.params["id"]).applyFilters(request, middlewares).exec;
      enforce!CrateNotFoundException(!result.empty, "Item not found.");

      next(request, response);
    }  

    return &localHandler;
  }
}


void updateHeaders(HTTPServerResponse response, HTTPServerRequest request, CrateRule rule, Json result) {
  foreach(string key, string value; rule.response.headers) {
    if(value.canFind(":base_uri")) {
      auto baseUri = request.fullURL.parentURL.toString;

      if(baseUri.endsWith("/")) {
        baseUri = baseUri[0..$-1];
      }

      value = value.replace(":base_uri", baseUri);
    }

    if(value.canFind(":id")) {
      value = value.replace(":id", result["_id"].get!string);
    }

    response.headers[key] = value;
  }
}

void checkFields(ref Json data, FieldDefinition definition, string prefix = "") @trusted {
  
  if(definition.isRelation && data.type == Json.Type.string) {
    auto type = definition.originalType;

    try {
      auto relation = crateGetters[type](data.to!string).exec;
      enforce!CrateValidationException(!relation.empty, "`" ~ prefix ~ "` is not a valid `" ~ type ~ "` relation.");
      data = relation.front;

      checkFields(data, definition, prefix);
    } catch (CrateNotFoundException e) {
      throw new CrateValidationException(e.msg, e.file, e.line, e);
    }


    return;
  }

  if(definition.isArray) {
    enforce!CrateValidationException(data.type == Json.Type.array,
      "`" ~ prefix ~ definition.name ~ "` should be an array instead of `" ~ data.type.to!string ~ "`.");

    foreach(size_t i, ref value; data) {
      checkFields(value, definition.fields[0],  prefix ~ "[" ~ i.to!string ~ "]");
    }

    return;
  }

  if(prefix != "") {
    prefix ~= ".";
  }

  foreach (field; definition.fields) {
    bool isSet = data[field.name].type !is Json.Type.undefined;
    bool canCheck = !field.isId && !field.isOptional && field.name != "";

    enforce!CrateValidationException(!canCheck || isSet, "`" ~ prefix ~ field.name ~ "` is required.");

    if(!isSet) {
      continue;
    }

    if(field.isArray) {
      checkFields(data[field.name], field, prefix ~ field.name);

      continue;
    }

    if(field.isRelation) {
      bool isValid = data[field.name].type != Json.Type.object && data[field.name].type != Json.Type.array;
      
      auto type = field.originalType;
      enforce!CrateValidationException(isValid, "`" ~ prefix ~ field.name ~ "` is a relation and it should contain an id.");
      enforce!CrateValidationException(type in crateGetters, "`" ~ prefix ~ field.name ~ "` can not be fetched because there is no `" ~ type ~ "` crate getter defined.");

      checkFields(data[field.name], field,  prefix ~ field.name);
      continue;
    }

    if(!field.isBasicType) {
      checkFields(data[field.name], field,  prefix ~ field.name);
    }
  }
}

void checkRelationships(ref Json data, FieldDefinition definition) @safe {
  foreach (field; definition.fields) {
    if(!field.isOptional && field.name != "" && data[field.name].type == Json.Type.undefined) {
      throw new CrateValidationException("`" ~ field.name ~ "` is missing");
    }

    if(field.isOptional && data[field.name].type == Json.Type.undefined) {
      continue;
    }
  }
}

/// Handle requests with id and without body
auto requestIdHandler(void delegate(string) @safe next, CrateRule rule) {
  enforce(next !is null, "The next handler was not set. ");

  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @safe {
    string id = request.params["id"];

    next(id);

    response.statusCode = rule.response.statusCode;
    response.writeVoidBody;
  }

  return &deserialize;
}

/// ditto
auto requestIdHandler(void delegate(string, HTTPServerResponse) @safe next, CrateRule rule) {
  enforce(next !is null, "The next handler was not set. ");

  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @safe {
    string id = request.params["id"];
    response.statusCode = rule.response.statusCode;
    next(id, response);
  }

  return &deserialize;
}

/// ditto
auto requestIdHandler(T)(T delegate(string) @safe getItem, CrateRule rule) if(!is(T == void) && !is(T == ICrateSelector)){
  enforce(getItem !is null, "The getItem handler was not set. ");

  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @safe {
    string id = request.params["id"];

    Json jsonResponse;

    try {
      jsonResponse = rule.response.serializer.denormalise(getItem(id).serializeToJson);
    } catch (JSONException e) {
      throw new CrateValidationException("Can not serialize data. " ~ e.msg, e.file, e.line);
    }

    response.writeJsonBody(jsonResponse, 200, rule.response.mime);
  }

  return &deserialize;
}

/// ditto
auto requestIdHandler(Types...)(ICrateSelector delegate(string) @safe getItem, CrateRule rule, Types filters) {
  enforce(getItem !is null, "The getItem handler was not set. ");

  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @trusted {
    string id = request.params["id"];

    Json jsonResponse;
    auto result = getItem(id).applyFilters(request, filters).exec;

    enforce!CrateNotFoundException(!result.empty, "Missing `" ~ rule.response.serializer.definition.type ~ "`.");

    try {
      jsonResponse = rule.response.serializer.denormalise(result.front);
    } catch (JSONException e) {
      throw new CrateValidationException("Can not serialize data. " ~ e.msg, e.file, e.line);
    }

    response.writeJsonBody(jsonResponse, 200, rule.response.mime);
  }

  return &deserialize;
}

/// ditto
auto requestDeserializationHandler(Type, V, U)(V delegate(U) @safe next, CrateRule rule) if(!is(V == void)) {
  enforce(next !is null, "The next handler for `" ~ Type.stringof ~ "` was not set. ");

  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @safe {
    string id;

    if("id" in request.params) {
      id = request.params["id"];
    }

    auto clientData = rule.request.serializer.normalise(id, request.json);
    Type value;
    Json result;

    checkRelationships(clientData, rule.request.serializer.definition);
    checkFields(clientData, rule.request.serializer.definition);

    try {
      value = clientData.deserializeJson!Type;

      static if(is(U == Json)) {
        result = next(value.serializeToJson).serializeToJson;
      } else {
        result = next(value).serializeToJson;
      }
    } catch (JSONException e) {
      throw new CrateValidationException("Can not deserialize data. " ~ e.msg, e.file, e.line);
    }
  
    response.statusCode = rule.response.statusCode;

    if(result.type == Json.Type.undefined || result.type == Json.Type.null_) {
      response.writeVoidBody;
    } else {
      response.writeJsonBody(rule.response.serializer.denormalise(result.serializeToJson), rule.response.mime);
    }
  }

  return &deserialize;
}

/// ditto
auto requestDeserializationHandler(Type, U)(void delegate(U, HTTPServerResponse) @safe next, CrateRule rule) if(!is(V == void)) {
  enforce(next !is null, "The next handler was not set. ");

  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @safe {
    string id;

    if("id" in request.params) {
      id = request.params["id"];
    }

    auto clientData = rule.request.serializer.normalise(id, request.json);
    Type value;
    Json result;

    checkRelationships(clientData, rule.request.serializer.definition);
    checkFields(clientData, rule.request.serializer.definition);

    value = clientData.deserializeJson!Type;

    static if(is(U == Json)) {
      next(value.serializeToJson, response);
    } else {
      next(value, response).serializeToJson;
    }
  }

  return &deserialize;
}

/// Call the next handler after the request data is deserialized
auto requestFullDeserializationHandler(U, T)(void delegate(T, HTTPServerResponse) @safe next, CrateRule rule) {
  enforce(next !is null, "The next handler was not set. ");

  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @safe {
    string id;

    if("id" in request.params) {
      id = request.params["id"];
    }

    auto clientData = rule.request.serializer.normalise(id, request.json);
    
    checkRelationships(clientData, rule.request.serializer.definition);
    checkFields(clientData, rule.request.serializer.definition);

    T value;

    try {
      value = clientData.deserializeJson!T;
    } catch (JSONException e) {
      throw new CrateValidationException("Can not deserialize data. " ~ e.msg, e.file, e.line);
    }

    response.statusCode = rule.response.statusCode;

    next(value, response);
  }

  return &deserialize;
}

/// ditto
auto requestDeserializedHandler(Policy, Type, V)(V delegate(Json) @safe setItem, CrateRule rule) {
  enforce(setItem !is null, "The setItem handler for `" ~ Type.stringof ~ "` was not set. ");

  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @trusted {
    string id;

    if("id" in request.params) {
      id = request.params["id"];
    }

    auto rawData = rule.request.serializer.normalise(id, request.json);

    checkFields(rawData, rule.request.serializer.definition);

    Type value = rawData.deserializeJson!Type;

    auto clientData = value.serializeToJson;

    static if(is(V  == void)) {
      setItem(clientData);
      response.statusCode = 204;
      response.writeVoidBody;
    } else static if(is(V == Json)) {
      auto result = setItem(clientData);
      response.updateHeaders(request, rule, result);
      response.statusCode = rule.response.statusCode;
      response.writeJsonBody(rule.response.serializer.denormalise(result), Policy.mime);
    } else {
      auto result = setItem(clientData);
      response.statusCode = rule.response.statusCode;
      response.writeJsonBody(rule.response.serializer.denormalise(result.serializeToJson), Policy.mime);
    }
  }

  return &deserialize;
}

/// ditto
auto requestDeserializedHandler(Policy, Type, V, U, Types...)(V delegate(Json) @safe setItem, U delegate(string) @safe getItem, CrateRule rule, Types middlewares) {
  enforce(setItem !is null, "The setItem handler for `" ~ Type.stringof ~ "` was not set. ");

  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @trusted {
    string id;
    id = request.params["id"];

    auto rangeData = getItem(id).exec;

    enforce!CrateNotFoundException(!rangeData.empty, "Item `" ~ id ~ "` not found.");

    Json oldData = rangeData.front;

    auto mixResult = mix(oldData, rule.request.serializer.normalise(id, request.json));

    auto clientData = mixResult.deserializeJson!Type.serializeToJson;

    static if(is(V == void)) {
      setItem(clientData);
      response.statusCode = 204;
      response.writeVoidBody;
    } else static if(is(V == Json)) {
      auto result = setItem(clientData);
      response.statusCode = rule.response.statusCode;
      response.writeJsonBody(rule.response.serializer.denormalise(result), Policy.mime);
    } else {
      auto result = setItem(clientData);
      response.statusCode = rule.response.statusCode;
      response.writeJsonBody(rule.response.serializer.denormalise(result.serializeToJson), Policy.mime);
    }
  }

  return &deserialize;
}


/// Handle a request that returns a list of elements
auto requestListHandler(U, T)(T[] delegate() @safe next) if(!is(T == void)) {
  enforce(next !is null, "The next handler was not set. ");

  FieldDefinition definition = getFields!T;
  auto serializer = new U.Serializer(definition);

  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @safe {
    Json jsonResponse;

    try {
      jsonResponse = serializer.denormalise(next().map!(a => a.serializeToJson).inputRangeObject);
    } catch (JSONException e) {
      throw new CrateValidationException("Can not serialize data. " ~ e.msg, e.file, e.line);
    }

    response.writeJsonBody(jsonResponse, 200, U.mime);
  }

  return &deserialize;
}

/// Handle a request that returns a list of elements before applying some filters
auto requestFilteredListHandler(U, T, Types...)(const ICrateSelector delegate() @safe get, Types filters) if(!is(T == void)) {
  FieldDefinition definition = getFields!T;
  auto serializer = new U.Serializer(definition);
  enforce(get !is null, "The get handler was not set. ");

  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @trusted {
    Json jsonResponse;

    try {
      auto items = get().applyFilters(request, filters);

      auto result = items.exec.array.inputRangeObject;
      jsonResponse = serializer.denormalise(result);
    } catch (JSONException e) {
      throw new CrateValidationException("Can not serialize data. " ~ e.msg, e.file, e.line);
    }

    response.writeJsonBody(jsonResponse, 200, U.mime);
  }

  return &deserialize;
}

auto requestActionHandler(Type, string actionName, T, U, V)(T delegate(string id) @system getElement, U delegate(V item) @system updateElement, CrateRule rule) 
    if(is(T == ICrateSelector) || is(T == Json) || is(T == Type)) {
  enforce(getElement !is null, "The getElement handler was not set. ");
  enforce(updateElement !is null, "The updateElement handler  was not set. ");

  void deserialize(HTTPServerRequest request, HTTPServerResponse response) @trusted {
    string id = request.params["id"];

    auto queryValue = getElement(id);

    static if(is(T == ICrateSelector)) {
      auto result = queryValue.exec;
      enforce!CrateNotFoundException(!result.empty, "Missing `" ~ Type.stringof ~ "`.");

      Type value = result.front.deserializeJson!Type;
    } else static if(is(T == Json)) {
      Type value = queryValue.deserializeJson!Type;
    } else {
      alias value = queryValue;
    }

    alias Func = typeof(__traits(getMember, value, actionName));
    
    static if(Parameters!Func.length == 0) {
      alias Param = void;
    } else {
      alias Param = Parameters!Func[0];
    }

    static if(is(ReturnType!Func == void)) {
      static if(is(Param == void)) {
        __traits(getMember, value, actionName)();
      } else {
        __traits(getMember, value, actionName)(request.bodyReader.readAllUTF8.to!Param);
      }

      static if(is(V == Json)) {
        updateElement(value.serializeToJson);
      } else {
        updateElement(value);
      }

      response.statusCode = rule.response.statusCode;
      
      response.writeVoidBody();
    } else {

      static if(is(Param == void)) {
        auto output = __traits(getMember, value, actionName)();
      } else {
        auto output = __traits(getMember, value, actionName)(request.bodyReader.readAllUTF8.to!Param);
      }

      static if(is(V == Json)) {
        updateElement(value.serializeToJson);
      } else {
        updateElement(value);
      }

      response.writeBody(output, rule.response.statusCode, rule.response.mime);
    }
  }

  return &deserialize;
}


Json mix(Json data, Json newData, string prefix = "")
{
  Json mixedData = data;
  enforce!CrateRelationNotFoundException(data.type == newData.type, "Invalid `" ~ prefix ~ "` type.");

  foreach (string key, value; newData)
  {
    if (mixedData[key].type == Json.Type.object)
    {
      mixedData[key] = mix(mixedData[key], value, prefix ~ (prefix == "" ? "" : ".") ~ key);
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
