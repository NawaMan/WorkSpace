#!/bin/bash
# This is to be run from with in the container.

mvn -q clean install exec:java 2>&1 \
  | grep -v 'sun.misc.Unsafe' \
  | grep -v 'com.google.inject.internal.aop.HiddenClassDefiner'
