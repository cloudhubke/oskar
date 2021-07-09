#!/bin/bash
set -e

cat > README.md <<'EOF'
# RPM Build Script

This file will create an RPM package from a given zip archive.

## Requirement

A Linux system with bash and docker as well as access to docker hub.

## Usage

Copy the file `ArangoDB-3.3.23.zip` and the script `build.sh` into
an empty directory.

Switch into this directory.

Run the script with the archive as sole argument

    ./build.sh ArangoDB-3.3.23.zip

This will generated the RPM, Debian and TAR archives for the given version.
EOF

DOCKER_IMAGE=arangodb/oskar:1.0

if test "$#" -ne 1; then
  echo "usage: $0 <archive>"
  exit 1
fi

NAME="$1"

if test ! -f "$NAME"; then
  echo "FATAL: archive '$NAME' not found"
  exit 1
fi

rm -rf builddir
mkdir builddir

(
  cd builddir

  case $NAME in
    *.zip)
      echo "INFO: extracting archive $NAME"
      unzip -q -x "../$NAME"
      ;;
    *.tar.gz)
      echo "INFO: extracting archive $NAME"
      tar xvf "../$NAME"
      ;;
    *)
      echo "FATAL: unknown archive type '$NAME'"
      exit 1
  esac
)

ARANGODB_FILE=$(basename builddir/ArangoDB-*)

echo "INFO: ArangoDB Version: $ARANGODB_FILE"
echo "INFO: cleaning old directories 'work' and 'oskar'"

docker run \
  --privileged \
  -v "$(pwd):/data" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  "$DOCKER_IMAGE" fish -c "rm -rf /data/oskar  /data/work"

mkdir work
mkdir oskar

echo "INFO: copying 'work/ArangoDB'"
cp -a "builddir/$ARANGODB_FILE" "work/ArangoDB"

cat > work/createPackage.fish <<'EOF'

mkdir -p "$OSKAR_HOME/oskar/work"

cp -a /oskar/* "$OSKAR_HOME/oskar"
cp -a /work/ArangoDB "$OSKAR_HOME/oskar/work"
cp -a /work/starter/arangodb "$OSKAR_HOME/oskar/work/starter/arangodb"

mkdir -p "$OSKAR_HOME/oskar/work/ArangoDB/upgrade-data-tests"

function createPackage
  cd "$OSKAR_HOME/oskar"
  source helper.fish

  findArangoDBVersion
  and asanOff
  and maintainerOff
  and releaseMode
  and community
  and set -xg NOSTRIP 1
  and echo "INFO: building 'ArangoDB'"
  and buildStaticArangoDB
  and echo "INFO: finished building 'ArangoDB'"
  and mkdir -p work/ArangoDB/build/install/usr/bin
  and cp "$OSKAR_HOME/oskar/work/starter/arangodb" "work/ArangoDB/build/install/usr/bin"
  and copyRclone
  and echo "INFO: building package"
  and buildPackage
end



function create
  createPackage
end

create
EOF

docker run \
  --privileged \
  -it \
  -e "OSKAR_HOME=$(pwd)" \
  -e "STARTER_VERSION=$STARTER_VERSION" \
  -v "$(pwd)/work:/work" \
  -v "$(pwd)/oskar:$(pwd)/oskar" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  "$DOCKER_IMAGE" fish /work/createPackage.fish

cp oskar/work/arangodb3*{rpm,deb,gz} .

echo "INFO: files have been created"
ls -l arangodb3*{rpm,deb,gz}
