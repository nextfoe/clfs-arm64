#!/bin/bash

. env.sh

aarch64-linux-gnu-gdb --command=./.gdb.cmd
