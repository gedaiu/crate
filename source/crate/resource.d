module crate.resource;

import vibe.core.stream;

import vibe.data.json;
import vibe.inet.webform;
import vibe.http.server;
import vibe.inet.webform;

import std.conv;
import std.file;
import std.stdio;

alias BodyOutputStream = typeof(HTTPServerResponse.bodyWriter);

interface CrateResource {
  string contentType();

  void write(BodyOutputStream bodyWriter);
  void read(const FilePart file);

  bool hasSize();
  ulong size();
}

version(unittest) {
  import fluent.asserts;
  import fluentasserts.vibe.request;
  import crate.collection.memory;

  class TestResource : CrateResource {
    static string lastRead;

    string contentType() {
      return "test/resource";
    }

    void write(BodyOutputStream bodyWriter) {
      bodyWriter.write("test body".to!(char[]));
    }

    void read(const FilePart file) {
      lastRead = readText(file.tempPath.toString);
    }

    bool hasSize() {
      return true;
    }

    ulong size() {
      return "test body".length;
    }

    override string toString() const @safe {
      return "test resource";
    }

    static TestResource fromString(string src) @safe {
      return new TestResource;
    }
  }

  struct ResourceEmbeded
  {
    string name = "test";
    TestResource resource = new TestResource;
  }

  struct ResourceModel
  {
    @optional string _id = "1";
    string name = "test";
    TestResource resource = new TestResource;
  }

  struct RelationModel
  {
    @optional string _id = "1";
    string name = "test";
    ResourceEmbeded relation;
  }

  struct ArrayModel
  {
    @optional string _id = "1";
    string name = "test";
    ResourceEmbeded[] relation = [ ResourceEmbeded() ];
  }
}

@("Access a model with resources")
unittest {
  import vibe.http.router;
  import crate.api.rest.policy;
  import crate.http.router;
  import std.stdio;

  auto router = new URLRouter();
  auto resourceCrate = new MemoryCrate!ResourceModel;

  resourceCrate.addItem(ResourceModel().serializeToJson);

  router
    .crateSetup
      .add(resourceCrate)
      .enableResource!(ResourceModel, "/resource")(resourceCrate);

  request(router)
    .get("/resourcemodels/1")
      .expectStatusCode(200)
      .end((Response response) => {
        assert(response.bodyJson["resourceModel"]["resource"] == "test resource");
      });

  request(router)
    .get("/resourcemodels/1/resource")
      .expectStatusCode(200)
      .expectHeader("Content-Type", "test/resource")
      .end((Response response) => {
        assert(response.bodyString == "test body");
      });


  string data = "-----------------------------9855312492823326321373169801\r\n";
  data ~= "Content-Disposition: form-data; name=\"resource\"; filename=\"resource.txt\"\r\n";
  data ~= "Content-Type: text/plain\r\n\r\n";
  data ~= "hello\r\n";
  data ~= "-----------------------------9855312492823326321373169801--\r\n";

  TestResource.lastRead = "";
  request(router)
    .header("Content-Type", "multipart/form-data; boundary=---------------------------9855312492823326321373169801")
    .post("/resourcemodels/1/resource")
    .expectStatusCode(201)
    .send(data)
    .end((Response response) => {
      assert(TestResource.lastRead == "hello");
    });

  data = "-----------------------------9855312492823326321373169801\r\n";
  data ~= "Content-Disposition: form-data; name=\"other\" filename=\"resource.txt\"\r\n";
  data ~= "Content-Type: text/plain\r\n\r\n";
  data ~= "hello\r\n";
  data ~= "-----------------------------9855312492823326321373169801--\r\n";

  TestResource.lastRead = "";
  request(router)
    .header("Content-Type", "multipart/form-data; boundary=---------------------------9855312492823326321373169801")
    .post("/resourcemodels/1/resource")
    .expectStatusCode(400)
    .send(data)
    .end((Response response) => {
      assert(TestResource.lastRead == "");
    });
}

@("Access a relation with resources")
unittest {
  import vibe.http.router;
  import crate.api.rest.policy;
  import crate.http.router;
  import std.stdio;

  auto router = new URLRouter();
  auto resourceCrate = new MemoryCrate!RelationModel;

  resourceCrate.addItem(RelationModel().serializeToJson);

  router
    .crateSetup
      .add(resourceCrate)
      .enableResource!(RelationModel, "/relation/resource")(resourceCrate);

  request(router)
    .get("/relationmodels/1")
      .expectStatusCode(200)
      .end((Response response) => {
        assert(response.bodyJson["relationModel"]["relation"]["resource"] == "test resource");
      });

  request(router)
    .get("/relationmodels/1/relation/resource")
      .expectStatusCode(200)
      .expectHeader("Content-Type", "test/resource")
      .end((Response response) => {
        assert(response.bodyString == "test body");
      });

  string data = "-----------------------------9855312492823326321373169801\r\n";
  data ~= "Content-Disposition: form-data; name=\"resource\"; filename=\"resource.txt\"\r\n";
  data ~= "Content-Type: text/plain\r\n\r\n";
  data ~= "hello\r\n";
  data ~= "-----------------------------9855312492823326321373169801--\r\n\r\n";

  request(router)
    .header("Content-Type", "multipart/form-data; boundary=---------------------------9855312492823326321373169801")
    .post("/relationmodels/1/relation/resource")
    .expectStatusCode(201)
    .send(data)
    .end((Response response) => {
      TestResource.lastRead.should.equal("hello");
    });
}

@("Access resources from an relation array")
unittest {
  import vibe.http.router;
  import crate.api.rest.policy;
  import crate.http.router;
  import std.stdio;

  auto router = new URLRouter();
  auto resourceCrate = new MemoryCrate!ArrayModel;

  resourceCrate.addItem(ArrayModel().serializeToJson);

  router
    .crateSetup
      .add(resourceCrate)
      .enableResource!(ArrayModel, "/relation/:index/resource")(resourceCrate);

  request(router)
    .get("/arraymodels/1")
      .expectStatusCode(200)
      .end((Response response) => {
        assert(response.bodyJson["arrayModel"]["relation"][0]["resource"] == "test resource");
      });

  request(router)
    .get("/arraymodels/1/relation/0/resource")
      .expectStatusCode(200)
      .expectHeader("Content-Type", "test/resource")
      .end((Response response) => {
        assert(response.bodyString == "test body");
      });

  string data = "-----------------------------9855312492823326321373169801\r\n";
  data ~= "Content-Disposition: form-data; name=\"resource\"; filename=\"resource.txt\"\r\n";
  data ~= "Content-Type: text/plain\r\n\r\n";
  data ~= "hello\r\n";
  data ~= "-----------------------------9855312492823326321373169801--\r\n";

  TestResource.lastRead = "";
  request(router)
    .header("Content-Type", "multipart/form-data; boundary=---------------------------9855312492823326321373169801")
    .post("/arraymodels/1/relation/0/resource")
    .expectStatusCode(201)
    .send(data)
    .end((Response response) => {
      assert(TestResource.lastRead == "hello");
    });
}
