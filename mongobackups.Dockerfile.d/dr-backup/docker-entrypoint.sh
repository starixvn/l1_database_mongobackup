#!/bin/bash

# Import key from secret
gpg --import /run/secrets/dr_key >/dev/null 2>&1

# If parameters are not start with a command, pass it to backup script
if [ "${1:0:1}" == "-" ]; then
  exec ./DRBackup.sh "$@"
fi

# Execute the input command otherwise
exec "$@"
