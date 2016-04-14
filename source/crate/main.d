module crate.main;
import std.getopt;

void crateMain(string[] args, void function() startWebServer)
{
	string arduinoPort = "";
	int webPort = 8080;

	auto helpInformation = getopt(args,
			"start", "Start web server", startWebServer,
			"generate-openapi", "Generate OpenApi documentation", &generateOpenApi,
			"webPort", "Web server port number", &webPort,
			"arduinoPort", "Arduino port name", &arduinoPort);

	if (helpInformation.helpWanted)
	{
		defaultGetoptPrinter("Some information about the program.", helpInformation.options);
	}
}

void generateOpenApi() {
  throw new Exception("not implemented");
}
