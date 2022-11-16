#!/bin/bash

if [ -z "$ROBBER_VERSION" ]; then
  echo "ROBBER_VERSION must be set" > /dev/stderr
  exit 1
fi

set -e

cd build/release-assets
for name in *; do
  if echo $name | grep -q $ROBBER_VERSION; then
    continue
  fi
  case $name in
    robber-*-devkit-*)
      new_name=$(echo $name | sed -e "s,devkit-,devkit-$ROBBER_VERSION-,")
      ;;
    robber-server-*|robber-portal-*|robber-inject-*|robber-gadget-*|robber-swift-*|robber-clr-*|robber-qml-*|gum-graft-*)
      new_name=$(echo $name | sed -E -e "s,^(robber|gum)-([^-]+),\\1-\\2-$ROBBER_VERSION,")
      ;;
    *)
      new_name=""
      ;;
  esac
  if [ -n "$new_name" ]; then
    mv -v $name $new_name
  fi
done
