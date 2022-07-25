#!/bin/bash

set -e

export GIT_TERMINAL_PROMPT=0

if [ "$1" != "--no-reset" ]; then
  echo "Warning: This will perform a reporeset and a reposync to make sure everything is up to date before mirroring"
  echo "If you do not want that to happen, abort now using CTRL+C and use the parameter --no-reset"
  echo "Otherwise, just confirm with ENTER"
  read
  echo
fi

pushd $TOP

source build/envsetup.sh

if [ "$1" != "--no-reset" ]; then
  reporeset
  reposync fast
fi

while read path; do
  echo "$path"
  repo_name=$(xmlstarlet sel -t -v "/manifest/project[@path='$path']/@name" $TOP/android/snippets/kasumi.xml)
  repo_mirror=$(xmlstarlet sel -t -v "/manifest/project[@path='$path']/@mirror" $TOP/android/snippets/kasumi.xml)
  echo "Mirror target: $repo_mirror"
  repo_remote=$(xmlstarlet sel -t -v "/manifest/project[@path='$path']/@remote" $TOP/android/snippets/kasumi.xml)

  pushd $TOP/$path

  if [[ ${ROM_VERSION} != $(git branch --show-current) ]]; then
    repo checkout $ROM_VERSION || repo start $ROM_VERSION
  fi

  echo "Setting mirror remote"
  if ! git ls-remote mirror >/dev/null 2>/dev/null; then
    if ! git remote add mirror $repo_mirror; then
      git remote set-url mirror $repo_mirror
    fi
  else
    git remote set-url mirror $repo_mirror
  fi

  if [ "$(git rev-parse --is-shallow-repository)" == "true" ]; then
    echo "Shallow repository detected, unshallowing first"
    git fetch --unshallow $repo_remote
  fi

  echo "Fetching mirror"
  git fetch mirror

  if [ "$path" == "external/tuuru" ]; then
    git push mirror HEAD:master
  else
    git push mirror HEAD:$ROM_VERSION
  fi
  popd

  echo
done < <(xmlstarlet sel -t -v '/manifest/project[@mirror]/@path' $TOP/android/snippets/kasumi.xml)

popd

echo "Everything done."
