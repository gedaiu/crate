module crate.routing.restapi;

import crate.base;
import std.string;


/// The default routes used by the REST API
class RestApiRouting {
  const { 
    FieldDefinition definition;
  }

  this(const FieldDefinition definition) pure {
    this.definition = definition;
  }

  string item() pure {
    return model() ~ "/:id";
  }

  string model() pure {
    return "/" ~ definition.plural.toLower;
  }

  alias get = item;
  alias put = item;
  alias delete_ = item;

  alias post = model;
  alias getList = model;
}
