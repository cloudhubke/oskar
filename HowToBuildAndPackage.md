# How to Build And Package

These instructions are for building .dmg(macOs) and .deb(debian) packages in a mac computer.

They have been tested to work on MacOs Big Sur (11.0.1);

Docker is required.

## Environment Variables

config/environment.fish

```
set -xg COMMUNITY_DOWNLOAD_LINK "https://community.arangodb.com"
set -xg ENTERPRISE_DOWNLOAD_LINK "https://enterprise.arangodb.com"

set -gx USE_CCACHE "sccache"
set -gx NOTARIZE_USER "exampleUser"
set -gx NOTARIZE_PASSWORD "examplePassword"
set -gx MACOS_ADMIN_KEYCHAIN_PASS "-"
```

## USE MAKE for development

Run the makeArangoDB in the oskar folder

```
fish
source config/environment.fish
source helper.fish
community

makeArangoDB
```

then run arangod in the while in the ArangoDb directory

```
cd work/ArangoDB

build/bin/arangod -c etc/relative/arangod.conf --server.endpoint tcp://127.0.0.1:8529 /tmp/database-dir

```

Run ArangoSh in another terminal while in the same folder

```
build/bin/arangosh
```

## Building DMG

```
fish
source config/environment.fish
source helper.fish
findArangoDBVersion
community
maintainerOff

buildCommunityPackage

```

the above commands will build the application and place the build files in work/ArangoDb/build/bin.

After that. It will run the `buildPackage` and generate .dmg files.

## Building .DEB

After generating the executables in above, now you can proceed to generate the debian files.

```
fish
source config/environment.fish
source helper.fish
source helper.linux.fish
community
maintainerOff
findArangoDBVersion

buildDebianPackage

```

if You get errors like `sed: -i: No such file or directory`

You may need to install another version of sed other than the one installed in macos.

```
brew install gnu-sed
```

then repeat

```
PATH="/usr/local/opt/gnu-sed/libexec/gnubin:$PATH"

fish
source config/environment.fish
source helper.fish
source helper.linux.fish
community
maintainerOff
findArangoDBVersion

buildDebianPackage

```
