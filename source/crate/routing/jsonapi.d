module crate.routing.jsonapi;

import crate.base;
import std.string;


/// The default routes used by the REST API
class JsonApiRouting {
  const { 
    FieldDefinition definition;
  }

  this(const FieldDefinition definition) {
    this.definition = definition;
  }

  string item() {
    return model() ~ "/:id";
  }

  string model() {
    return "/" ~ definition.plural.toLower;
  }

  alias get = item;
  alias put = item;
  alias delete_ = item;

  alias post = model;
  alias getAll = model;
}
