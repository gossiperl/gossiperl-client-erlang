#!/bin/bash
SCRIPT_DIRECTORY=$(dirname "${BASH_SOURCE[0]}")
DIR=$SCRIPT_DIRECTORY/../.gossiperl-daemon
rm -Rf $DIR && mkdir -p $DIR && cd $DIR
git clone https://github.com/gossiperl/gossiperl.git .
cd ..
chmod +x $DIR/test/run-for-unit-tests.sh
$DIR/test/run-for-unit-tests.sh
