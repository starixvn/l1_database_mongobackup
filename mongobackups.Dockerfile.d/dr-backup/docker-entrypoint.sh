#!/bin/bash

KEY_PATH="/run/secrets/dr_key"

# Import key from secret
if [ -f $KEY_PATH ]; then
  KEY_FP=$( gpg --quiet --import-options import-show --import $KEY_PATH | sed -e '2!d' -e 's/^[ \t]*//' ) && echo "${KEY_FP}:6:" | gpg --import-ownertrust >/dev/null 2>&1
else
  echo "File $KEY_PATH does not exist. Aborting..."
  exit 1
fi

# If parameters are not start with a command, pass it to backup script
if [ "${1:0:1}" == "-" ]; then
  exec ./DRBackup.sh "$@"
fi

# Execute the input command otherwise
exec "$@"
