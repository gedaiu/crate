module tests.crate.http.router.mocks;

import vibe.data.json;

static immutable restSiteFixture = `{
  "site": {
    "position": {
      "type": "Point",
      "coordinates": [0, 0]
    }
  }
}`;

static immutable jsonSiteFixture = `{
  "data": {
    "type": "sites",
    "attributes": {
      "position": {
        "type": "Point",
        "coordinates": [0, 0]
      }
    }
  }
}`;