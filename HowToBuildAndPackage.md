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
