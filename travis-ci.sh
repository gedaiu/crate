#!/bin/bash
set -e -x -o pipefail

# test for successful 32-bit build
if [ "$DC" == "dmd" ]; then
	dub build --arch=x86 --compiler=$DC -v
	dub clean --all-packages -v
fi

# test for successful release build
dub build -b release --compiler=$DC -v
dub clean --all-packages -v

# run unit tests
dub test --compiler=$DC -v
