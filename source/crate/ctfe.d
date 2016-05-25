module crate.ctfe;

import crate.base;
import vibe.data.json;

import std.meta;
import std.algorithm.searching;

import std.traits, std.meta;

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

		alias FieldType = ArrayType!(FT);
	}
	else static if (isAssociativeArray!(FT))
	{
		alias FieldType = ValueType!(FT);
	}
	else
	{
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
		static if (__traits(hasMember, T, "id") || __traits(hasMember, T, "_id"))
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

template getFields(Prototype)
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
		else static if (FIELDS.length == 1)
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
					alias Type = FieldType!(ItemProperty!(Prototype, FIELDS[0]));
					alias OriginalType = OriginalFieldType!(ItemProperty!(Prototype, FIELDS[0]));

					enum fieldName = FieldName!(FIELDS[0], Prototype);
					enum isId = IsId!(FIELDS[0]);
					enum isOptional = IsOptional!(FIELDS[0], Prototype);

					static if (IsBasicType!Type)
					{
						enum fields = [];
						enum singular = "";
						enum plural = "";
					}
					else
					{
						enum fields = getFields!Type.fields;
						enum singular = Singular!Type;
						enum plural = Plural!Type;
					}

					alias ItemFields = AliasSeq!([FieldDefinition(fieldName,
							FIELDS[0], attributes, Type.stringof, IsBasicType!Type,
							IsRelation!Type, isId, isOptional, isArray!OriginalType
							&& !is(OriginalType == string), fields, singular, plural)]);
				}
			}
			else
			{
				alias ItemFields = AliasSeq!();
			}
		}
		else
			alias ItemFields = AliasSeq!();
	}

	mixin("enum list = [ " ~ Join!(ItemFields!(__traits(allMembers, Prototype))) ~ " ];");

	enum fieldDefinition = FieldDefinition("", "", [], Prototype.stringof, false,
				false, false, false, false, list, Singular!Prototype, Plural!Prototype);

	alias getFields = fieldDefinition;
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

version (unittest)
{
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
