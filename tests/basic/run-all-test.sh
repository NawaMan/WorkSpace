#!/bin/bash

for f in test0*.sh ; do
    echo $f
    ./$f
    echo ""
done