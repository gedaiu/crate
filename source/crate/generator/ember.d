module crate.generator.ember;

import std.stdio, std.file, std.uni, std.conv;

import crate.ctfe;
import crate.base;
import crate.http.router;

import vibe.data.json;

void toEmber(T)(CrateRouter router, string path)
{
	enum FieldDefinition definition = getFields!T;
	enum FieldDefinition[] fields = definition.fields;

	void exportRelations(FieldDefinition[] fields)()
	{
		static if (fields.length > 0 && !fields[0].isBasicType)
		{
			createModel!(fields[0])(path, router.policy);
		}

		static if (fields.length > 1)
		{
			exportRelations!(fields[1 .. $])();
		}
	}

	void exportRESTSerializers(FieldDefinition[] fields)()
	{
		static if (fields.length == 0)
		{
			return;
		}
		else static if (!fields[0].isBasicType)
		{
			createRESTSerializer!(fields[0])(path);
			exportRESTSerializers!(fields[0].fields)();
		}

		static if (fields.length > 1)
		{
			exportRESTSerializers!(fields[1 .. $])();
		}
	}

	createModel!definition(path, router.policy);
	exportRelations!(fields);

	if (router.policy.name == "Rest API")
	{
		exportRESTSerializers!(fields);
		createRESTSerializer!definition(path);
	}
}

void createRESTSerializer(FieldDefinition definition)(string path)
{
	static if (definition.singular != "BsonObjectID")
	{
		mkdirRecurse(path ~ "/app/serializers/");

		string document = "import DS from 'ember-data';\n";

		document ~= "export default DS.RESTSerializer.extend(DS.EmbeddedRecordsMixin, {\n";

		string glue;
		string id;
		string attr;

		foreach (field; definition.fields)
		{
			if (field.isId)
			{
				id = field.name;
			}

			if (!field.isBasicType && !field.isRelation && field.type != "BsonObjectID")
			{
				attr ~= glue ~ "    " ~ field.name ~ ": { embedded: 'always' }";
				glue = ",\n";
			}
		}

		glue = "";
		if (attr != "")
		{
			document ~= "  attrs: {\n" ~ attr ~ "  \n}";
			glue = ",\n";
		}

		if (id != "id" && id != "")
		{
			document ~= glue ~ "  primaryKey: '" ~ id ~ "'";
		}

		document ~= "\n});\n";

		if (glue != "" || id != "id")
		{
			auto f = File(path ~ "/app/serializers/" ~ definition.singular.toDashes ~ ".js", "w");

			f.write(document);
		}
	}
}

void createAdapter(FieldDefinition definition)(string path, const CratePolicy policy)
{
	mkdirRecurse(path ~ "/app/adapters/");

	string document = "import DS from 'ember-data'\n";
	document ~= "import AppAdapter from '../mixins/app-adapter'\n\n";

	if (policy.name == "Rest API")
	{
		document ~= "export default DS.RESTAdapter.extend(AppAdapter);\n";
	}
	else
	{
		document ~= "export default DS.JSONAPIAdapter.extend(AppAdapter);\n";
	}

	auto f = File(path ~ "/app/adapters/" ~ definition.singular.toDashes ~ ".js", "w");
	f.write(document);
}

void createModel(FieldDefinition definition)(string path, const CratePolicy policy)
{
	static if (definition.singular != "BsonObjectID")
	{
		createAdapter!definition(path, policy);

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
				document ~= "  " ~ modelField(policy, field);
			}
		}

		document ~= "});\n";

		auto f = File(path ~ "/app/models/" ~ definition.singular.toDashes ~ ".js", "w");

		f.write(document);
	}
}

private
{
	string modelField(const CratePolicy policy, FieldDefinition field)
	{
		string fieldString = "";
		string type = field.type.toEmberType(policy);
		string options;

		if(!field.isRelation && !field.isBasicType) {
			options = ", { async: false }";
		}

		if (type != "")
		{
			type = "'" ~ type ~ "'";
		}

		if (field.isArray)
		{
			fieldString ~= field.name ~ ": DS.hasMany(" ~ type ~ options ~ "), \n";
		}
		else if (field.isRelation)
		{
			fieldString ~= field.name ~ ": DS.belongsTo(" ~ type ~ options  ~ "), \n";
		}
		else
		{
			fieldString ~= field.name ~ ": DS.attr(" ~ type ~ options  ~ "), \n";
		}

		return fieldString;
	}

	string toEmberType(string dType, const CratePolicy policy)
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

		case "BsonObjectID":
		case "string":
			return "string";

		case "bool":
			return "boolean";

		case "SysTime":
		case "DateTime":
			return "date";

		default:
			if (policy.name == "Rest API")
			{
				return dType.toDashes;
			}
		}

		return "";
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

	string toFirstLower(string name)
	{
		return name[0 .. 1].toLower ~ name[1 .. $];
	}
}
