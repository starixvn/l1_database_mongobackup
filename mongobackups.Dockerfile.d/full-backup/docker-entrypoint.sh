#!/bin/bash

# If parameters are not start with a command, pass it to FullBackup script
if [ "${$1:0:1}" == "-" ]; then
  exec "./FullBackup.sh $@"
fi

# Execute the input command otherwise
exec "$@"
