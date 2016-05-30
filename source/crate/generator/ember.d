module crate.generator.ember;

import std.stdio, std.file, std.uni, std.conv;

import crate.ctfe;
import crate.base;
import crate.router;

void toEmber(T)(CrateRouter router, string path)
{

	alias fields = getFields!T;

	writeln(fields);

	createModel!fields(path);
}

void createModel(FieldDefinition definition)(string path)
{
	mkdirRecurse(path ~ "/app/models/");
	string document = "import DS from 'ember-data';\n\n";

	document ~= "export default DS.Model.extend({\n";

	foreach (field; definition.fields)
	{
    if (!field.isId) {
		  document ~= "  " ~ modelField(field);
    }
	}

	document ~= "});\n";

	auto f = File(path ~ "/app/models/" ~ definition.singular.toDashes ~ ".js", "w");

	f.write(document);
}

private
{
	string modelField(FieldDefinition field)
	{
		string fieldString = "";

		if (field.isArray)
		{
			fieldString ~= field.name ~ ": DS.hasMany('" ~ field.type.toEmberType ~ "'), \n";
		}
		else if (field.isRelation)
		{
			fieldString ~= field.name ~ ": DS.belongsTo('" ~ field.type.toEmberType ~ "'), \n";
		}
		else
		{
			fieldString ~= field.name ~ ": DS.attr('" ~ field.type.toEmberType ~ "'), \n";
		}

		return fieldString;
	}

	string toEmberType(string dType)
	{
		switch (dType)
		{
		case "int":
			return "number";

		case "string":
			return "string";

		case "bool":
			return "boolean";

		case "SysTime":
		case "DateTime":
			return "date";

		default:
			return dType.toDashes;
		}
	}

	string toDashes(string value)
	{
		string result = value[0].toLower.to!string;

		foreach (ch; value[1 .. $])
		{
			if (ch == ch.toUpper)
			{
				result ~= "-" ~ ch.toLower.to!string;
			}
			else
			{
				result ~= ch;
			}
		}

		return result;
	}
}
