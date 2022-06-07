#!/bin/bash

# If parameters are not start with a command, pass it to FullBackup script
if [ "${$1:0:1}" == "-" ]
  exec "./FullBackup.sh $@"

# Execute the input command otherwise
exec "$@"
