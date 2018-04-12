module crate.routing.restapi;

import crate.base;
import std.string;


class RestApiRouting {
  const { 
    FieldDefinition definition;
  }

  this(const FieldDefinition definition) {
    this.definition = definition;
  }

  string put() {
    return "/" ~ definition.plural.toLower ~ "/:id";
  }

  string get() {
    return "/" ~ definition.plural.toLower ~ "/:id";
  }

  string delete_() {
    return "/" ~ definition.plural.toLower ~ "/:id";
  }

  string post() {
    return "/" ~ definition.plural.toLower;
  }

}