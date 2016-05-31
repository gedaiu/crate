module crate.generator.ember;

import std.stdio, std.file, std.uni, std.conv;

import crate.ctfe;
import crate.base;
import crate.router;

void toEmber(T)(CrateRouter router, string path)
{
	enum FieldDefinition definition = getFields!T;
	enum FieldDefinition[] fields = definition.fields;

	void exportRelations(FieldDefinition[] fields)() {
		static if(fields.length > 0 && fields[0].isRelation) {
			createModel!(fields[0])(path);
		}

		static if(fields.length > 1) {
			exportRelations!(fields[1..$])();
		}
	}

	createModel!definition(path);

	exportRelations!(fields);
}

void createModel(FieldDefinition definition)(string path)
{
	mkdirRecurse(path ~ "/app/models/");
	string document = "import DS from 'ember-data';\n";
	document ~= "import Ember from 'ember'; \n\n";
	document ~= "var inflector = Ember.Inflector.inflector; \n\n";
	document ~= "inflector.irregular('" ~ definition.singular.toFirstLower
		~ "', '" ~ definition.plural.toFirstLower ~ "'); \n\n";

	document ~= "export default DS.Model.extend({\n";

	foreach (field; definition.fields)
	{
		if (!field.isId)
		{
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
		case "byte":
		case "ubyte":
		case "short":
		case "ushort":
		case "int":
		case "uint":
		case "long":
		case "ulong":
		case "float":
		case "double":
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

	string toFirstLower(string name) {
		return name[0..1].toLower ~ name[1..$];
	}
}
