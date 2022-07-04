#!/bin/bash

# If parameters are not start with a command, pass it to backup script
if [ "${1:0:1}" == "-" ]; then
  exec ./FullBackup.sh "$@"
fi

# Execute the input command otherwise
exec "$@"
