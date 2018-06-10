module crate.ctfe;

import crate.base;
import vibe.data.json;
import vibe.data.serialization;

import std.algorithm.searching;

import std.traits, std.meta;
import std.typetuple;
import std.datetime;
import std.exception;

template OriginalFieldType(alias F)
{
  static if (is(FunctionTypeOf!F == function))
  {
    static if (is(ReturnType!(F) == void) && arity!(F) == 1)
    {
      alias OriginalFieldType = Unqual!(ParameterTypeTuple!F);
    }
    else
    {
      alias OriginalFieldType = Unqual!(ReturnType!F);
    }
  }
  else
  {
    alias OriginalFieldType = typeof(F);
  }
}

template ArrayType(T : T[])
{
  alias ArrayType = T;
}

template FieldType(alias F)
{
  alias FT = OriginalFieldType!F;

  static if (!isSomeString!(FT) && isArray!(FT))
  {
    alias FieldType = Unqual!(FT);
  }
  else static if (isAssociativeArray!(FT))
  {
    alias FieldType = ValueType!(FT);
  }
  else {
    alias FieldType = Unqual!(FT);
  }
}

/**
 * Get all attributes
 */
template GetAttributes(string name, Prototype)
{
  template GetFuncAttributes(TL...)
  {
    static if (TL.length == 1)
    {
      alias GetFuncAttributes = AliasSeq!(__traits(getAttributes, TL[0]));
    }
    else static if (TL.length > 1)
    {
      alias GetFuncAttributes = AliasSeq!(GetFuncAttributes!(TL[0 .. $ / 2]),
          GetFuncAttributes!(TL[$ / 2 .. $]));
    }
    else
    {
      alias GetFuncAttributes = AliasSeq!();
    }
  }

  static if (is(FunctionTypeOf!(ItemProperty!(Prototype, name)) == function))
  {
    static if (__traits(getOverloads, Prototype, name).length == 1)
    {
      alias GetAttributes = AliasSeq!(__traits(getAttributes,
          ItemProperty!(Prototype, name)));
    }
    else
    {
      alias GetAttributes = AliasSeq!(GetFuncAttributes!(AliasSeq!(__traits(getOverloads,
          Prototype, name))));
    }
  }
  else
  {
    alias GetAttributes = AliasSeq!(__traits(getAttributes, ItemProperty!(Prototype, name)));
  }
}

template StringOfSeq(TL...)
{
  static if (TL.length == 1)
  {
    static if (is(typeof(TL[0]) == string))
      alias StringOfSeq = AliasSeq!(TL[0]);
    else
    {
      enum strVal = TL[0].stringof;
      alias StringOfSeq = AliasSeq!(strVal);
    }
  }
  else static if (TL.length > 1)
  {
    alias StringOfSeq = AliasSeq!(StringOfSeq!(TL[0 .. $ / 2]), StringOfSeq!(TL[$ / 2 .. $]));
  }
  else
  {
    alias StringOfSeq = AliasSeq!();
  }
}

/**
 * Get a class property.
 *
 * Example:
 * --------------------
 * class BookItemPrototype {
 * 	@("field", "primary")
 *	ulong id;
 *
 *	@("field") string name = "unknown";
 * 	@("field") string author = "unknown";
 * }
 *
 * assert(__traits(isIntegral, ItemProperty!(BookItemPrototype, "id")) == true);
 * --------------------
 */
template ItemProperty(item, string method)
{
  static if (__traits(hasMember, item, method))
  {
    static if (__traits(getProtection, mixin("item." ~ method)).stringof[1 .. $ - 1] == "public")
    {
      alias ItemProperty = AliasSeq!(__traits(getMember, item, method));
    }
    else
    {
      alias ItemProperty = AliasSeq!();
    }
  }
  else
  {
    alias ItemProperty = AliasSeq!();
  }
}

template Join(List...)
{

  static if (List.length == 1)
  {
    enum l = List[0].stringof[1 .. $ - 1];
  }
  else static if (List.length > 1)
  {
    enum l = List[0].stringof[1 .. $ - 1] ~ ", " ~ Join!(List[1 .. $]);
  }
  else
  {
    enum l = "";
  }

  alias Join = l;
}

template IsBasicType(T)
{
  static if (isBasicType!T || is(T == string))
  {
    enum isBasicType = true;
  }
  else
  {
    enum isBasicType = false;
  }

  alias IsBasicType = isBasicType;
}

template IsRelation(T)
{
  static if (is(T == class) || is(T == struct))
  {
    static if (!isStringSerializable!T && (__traits(hasMember, T, "id") || __traits(hasMember, T, "_id")))
    {
      enum isRelation = true;
    }
    else
    {
      enum isRelation = false;
    }
  }
  else
  {
    enum isRelation = false;
  }

  alias IsRelation = isRelation;
}

template IsOptional(string property, Prototype)
{
  enum attributes = [StringOfSeq!(GetAttributes!(property, Prototype))];

  static if ((cast(string[]) attributes).canFind("optional()", "optional"))
  {
    enum isOptional = true;
  }
  else
  {
    enum isOptional = false;
  }

  alias IsOptional = isOptional;
}

template IsId(string name)
{
  static if (name == "id" || name == "_id")
  {
    enum isId = true;
  }
  else
  {
    enum isId = false;
  }

  alias IsId = isId;
}

template FieldName(string property, Prototype)
{
  alias NameAttr = typeof(name(""));

  static if (hasUDA!(ItemProperty!(Prototype, property), NameAttr))
  {
    enum fieldName = getUDAs!(ItemProperty!(Prototype, property), NameAttr)[0].name;
  }
  else
  {
    enum fieldName = property;
  }

  alias FieldName = fieldName;
}

template DescribeBasicType(Prototype, alias FIELD, alias attributes) {
  alias T = FieldType!(ItemProperty!(Prototype, FIELD));

  static if (isStringSerializable!T) {
    alias Type = string;
  } else {
    alias Type = T;
  }

  alias OriginalType = OriginalFieldType!(ItemProperty!(Prototype, FIELD));

  enum DescribeBasicType = FieldDefinition(
    FieldName!(FIELD, Prototype), //name
    FIELD,                        //originalName
    attributes,                   //attributes
    Type.stringof,                //type
    OriginalType.stringof,        //originalType
    true,                         //isBasicType
    false,                        //isRelation
    IsId!FIELD,                   //isId
    IsOptional!(FIELD, Prototype),//isOptional
    false,                        //isArray
    [],                           //fields
    "",                           //singular
    ""                            //plural
  );
}

template Describe(T, alias name = "") {
  static if (isStringSerializable!T) {
    alias Type = string;
  } else {
    alias Type = T;
  }

  static if (IsBasicType!Type || isStringSerializable!Type)
  {
    enum Describe = FieldDefinition(
      name,          //name
      name,          //originalName
      [],            //attributes
      Type.stringof, //type
      T.stringof,    //originalType
      true,          //isBasicType
      false,         //isRelation
      false,         //isId
      false,         //isOptional
      false,         //isArray
      [],            //fields
      "",            //singular
      ""             //plural
    );
  }
  else static if( isArray!Type )
  {
    enum Describe = DescribeArrayField!(Type, name);
  }
  else
  {
    alias Describe = getFields!(Type, name, true);
  }
}

template DescribeArrayField(Prototype, alias name = "") {
  alias ValueType = ArrayType!Prototype;

  enum DescribeArrayField = FieldDefinition(
    name,                            //name
    name,                            //originalName
    [],                            //attributes
    Prototype.stringof,            //type
    Prototype.stringof,            //originalType
    false,                         //isBasicType
    false,                         //isRelation
    false,                         //isId
    false,                         //isOptional
    true,                          //isArray
    [ Describe!ValueType ],        //fields
    "",                            //singular
    ""                             //plural
  );
}

template DescribeArrayField(Prototype, alias FIELD, alias attributes) {
  alias Type = FieldType!(ItemProperty!(Prototype, FIELD));

  alias OriginalType = OriginalFieldType!(ItemProperty!(Prototype, FIELD));
  alias ValueType = ArrayType!OriginalType;

  enum DescribeArrayField = FieldDefinition(
    FieldName!(FIELD, Prototype),  //name
    FIELD,                         //originalName
    attributes,                    //attributes
    Type.stringof,                 //type
    OriginalType.stringof,         //originalType
    false,                         //isBasicType
    false,                         //isRelation
    false,                         //isId
    IsOptional!(FIELD, Prototype), //isOptional
    true,                          //isArray
    [ Describe!ValueType ],        //fields
    "",                            //singular
    ""                             //plural
  );
}

template Describe(Prototype, alias FIELD, alias attributes) {
  alias T = FieldType!(ItemProperty!(Prototype, FIELD));

  static if (isStringSerializable!T) {
    alias Type = string;
  } else {
    alias Type = T;
  }

  static if (IsBasicType!Type || isStringSerializable!Type)
  {
    alias Describe = DescribeBasicType!(Prototype, FIELD, attributes);
  }
  else static if( isArray!Type )
  {
    alias Describe = DescribeArrayField!(Prototype, FIELD, attributes);
  }
  else
  {
    alias Describe = getFields!(Type, FieldName!(FIELD, Prototype), true, attributes);
  }
}

template getFields(Prototype, alias name = "", alias isNested = false, alias attributes = []) if(isAggregateType!Prototype)
{
  /**
   * Get all the metods
   */
  template ItemFields(FIELDS...)
  {
    static if (FIELDS.length > 1)
    {
      alias ItemFields = AliasSeq!(ItemFields!(FIELDS[0 .. $ / 2]),
          ItemFields!(FIELDS[$ / 2 .. $]));
    }
    else static if (FIELDS.length == 1 && FIELDS[0] != "Monitor" && FIELDS[0] != "factory")
    {
      static if (ItemProperty!(Prototype, FIELDS[0]).length == 1)
      {
        enum attributes = [StringOfSeq!(GetAttributes!(FIELDS[0], Prototype))];

        static if ((cast(string[]) attributes).canFind("ignore()", "ignore")
            || isSomeFunction!(ItemProperty!(Prototype, FIELDS[0])))
        {
          alias ItemFields = AliasSeq!();
        }
        else
        {
          alias ItemFields = Describe!(Prototype, FIELDS[0], attributes);
        }
      }
      else
      {
        alias ItemFields =  AliasSeq!();
      }
    }
    else
      alias ItemFields =  AliasSeq!();
  }

  enum fields = [ ItemFields!(__traits(allMembers, Prototype)) ];

  static if(isNested) {
    alias isRelation = IsRelation!Prototype;
  } else {
    enum isRelation = false;
  }

  enum isOptional = (cast(string[]) attributes).canFind("optional()", "optional") == 1;

  enum getFields = FieldDefinition(
    name,                //name
    name,                //originalName
    [],                  //attributes
    Prototype.stringof,  //type
    Prototype.stringof,  //originalType
    false,               //isBasicType
    isRelation,          //isRelation
    false,               //isId
    isOptional,          //isOptional
    false,               //isArray
    fields,              //fields
    Singular!Prototype,  //singular
    Plural!Prototype);   //plural
}

private string prefixedAttribute(string prefix, string defaultValue, attributes...)()
{
  static if (attributes.length == 0)
  {
    return defaultValue;
  }
  else
  {
    import std.string : strip;

    auto len = prefix.length;

    foreach (value; attributes)
    {
      if (value.length > len && value[0 .. len] == prefix)
      {
        return value[len .. $].strip;
      }
    }

    return defaultValue;
  }
}


FieldDefinition[] extractArrayObjects(FieldDefinition definition) pure {
  enforce(definition.isArray);

  if(definition.fields[0].isArray) {
    return definition.fields[0].extractArrayObjects;
  }

  if(!definition.fields[0].isBasicType) {
    return [ definition.fields[0] ] ~ definition.fields[0].extractObjects;
  }

  return [];
}

FieldDefinition[] extractObjects(FieldDefinition definition) pure {
  FieldDefinition[] result;

  foreach(field; definition.fields) {
    if(field.isArray) {
      result ~= field.extractArrayObjects;
    } else if(!field.isBasicType) {
      result ~= [ field ] ~ field.extractObjects;
    }
  }

  return result;
}

template Plural(Type)
{
  import std.uni : toLower;

  enum ATTR = __traits(getAttributes, Type);
  enum defaultPlural = Type.stringof ~ "s";
  enum plural = prefixedAttribute!("plural:", defaultPlural, ATTR)();

  alias Plural = plural;
}

template Singular(Type)
{
  import std.uni : toLower;

  enum ATTR = __traits(getAttributes, Type);
  enum defaultSingular = Type.stringof;
  enum singular = prefixedAttribute!("singular:", defaultSingular, ATTR)();

  alias Singular = singular;
}

version(unittest)
{
  import fluent.asserts;

  struct ActionModel
  {
    string _id;
    string name;

    void action()
    {
    }
  }
}

unittest
{
  enum def = getFields!ActionModel;

  foreach (field; def.fields)
  {
    assert(field.name != "action");
  }

  assert(def.fields.length == 2);
}

unittest {
  struct StringSerializable {
    string toString() const {
      return "";
    }

    static StringSerializable fromString(string) {
      throw new Exception("");
    }
  }

  struct Model {
    string _id;
    StringSerializable str;
  }

  enum def = getFields!Model;

  assert(def.fields[1].originalName == "str");
  assert(def.fields[1].originalType == "StringSerializable");
  assert(def.fields[1].type == "string");
}

@("Describe nested arrays")
unittest {
  struct NestedArrays {
    double[2][] coordinates;
  }

  enum def = getFields!NestedArrays;

  def.fields[0].name.should.equal("coordinates");
  def.fields[0].isArray.should.equal(true);
  def.fields[0].originalType.should.equal("double[2][]");

  def.fields[0].fields[0].isArray.should.equal(true);
  def.fields[0].fields[0].originalType.should.equal("double[2]");
  def.fields[0].fields[0].isBasicType.should.equal(false);

  def.fields[0].fields[0].fields[0].isArray.should.equal(false);
  def.fields[0].fields[0].fields[0].originalType.should.equal("double");
  def.fields[0].fields[0].fields[0].isBasicType.should.equal(true);
}

template isVibeHandler(Type, alias member) {
  import vibe.http.server: HTTPServerRequest, HTTPServerResponse;

  static if(__traits(hasMember, Type, member)) {
    static foreach (Method; __traits(getOverloads, Type, member)) {
      static if(Parameters!Method.length == 2 && 
        is(Parameters!Method[0] == HTTPServerRequest) && 
        is(Parameters!Method[1] == HTTPServerResponse)) {
        
        enum result = true;
      }
    }
  }

  static if(!__traits(compiles, result)) {
    enum result = false;
  }

  alias isVibeHandler = result;
}

template isCrateFilter(Type, alias member) {
  import vibe.http.server: HTTPServerRequest, HTTPServerResponse;

  static if(__traits(hasMember, Type, member)) {
    static foreach (Method; __traits(getOverloads, Type, member)) {
      static if(Parameters!Method.length == 2 && 
        is(Parameters!Method[0] == HTTPServerRequest) && 
        is(Parameters!Method[1] == ICrateSelector)) {
        
        enum result = true;
      }
    }
  }

  static if(!__traits(compiles, result)) {
    enum result = false;
  }

  alias isCrateFilter = result;
}