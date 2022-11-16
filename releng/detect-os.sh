#!/bin/sh

if [ -n "$ROBBER_BUILD_OS" ]; then
  echo $ROBBER_BUILD_OS
  exit 0
fi

echo $(uname -s | tr '[A-Z]' '[a-z]' | sed 's,^darwin$,macos,')
