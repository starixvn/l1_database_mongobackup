#!/bin/bash

SCRIPT_VERSION=1.0.0
SCRIPT_LABEL=FULLBACKUP

################################################################################
###   FUNCTIONS
#

# Usage function
usage() {
  echo "$SCRIPT_LABEL version: $SCRIPT_VERSION
    -h  --help                    Print this help
        --host                    Input mongodb host address
        --port                    Input mongodb port
    -V  --version                 Print version info
    -v  --verbose                 Enable verbose logging
        --uri                     Input mongodb URI connection string
    -u  --username                Input mongodb username to connect
    -p  --password                Input user's password to authenticate
        --authenticationDatabase  Input database where user will be authenticated
        --backupPath              Input the path to save the backup file
        --backupName              Input the name of the backup file (no extension)
        --dataPath                Input the path contains data files

    [to be updated]
  " 1>&2
  exit 2
}

# Version function
version() {
  echo "$SCRIPT_LABEL version: $SCRIPT_VERSION" 1>&2
  echo "---" 1>&2
  echo "mongosh version: $(mongosh --version)" 1>&2
  echo "---" 1>&2
  mongodump --version
  echo "---" 1>&2
  mongorestore --version
  exit 0
}

# Verbose function
verbose() {
  local ACTIVATE=$VERBOSE
  local LABEL="V"
  if [ "$ERROR" == true ]; then
    ACTIVATE=true
    LABEL="E"
  fi
  if [ "$INFO" == true ]; then
    ACTIVATE=true
    LABEL="I"
  fi
  if [ "$ACTIVATE" == true ]; then
    local FLAG=$1
    shift 1
    local REST="$@"
    if [ ! -z "$REST" ]; then
      echo "$(date -u "+%Y-%m-%dT%H:%M:%S.%3N%z") $LABEL  $SCRIPT_LABEL [$FLAG] $REST"
    else
      echo "$(date -u "+%Y-%m-%dT%H:%M:%S.%3N%z") $LABEL  $SCRIPT_LABEL [-] $FLAG $REST"
    fi
  fi
}

# UrlEncode function
urlencode() {
  local STR="$1"
  local LEN=${#STR}
  local RES=
  local i o
  local COLLATE_BK=$LC_COLLATE
  LC_COLLATE=C

  for (( i=0; i<LEN; i++ )); do
    local char="${STR:$i:1}"
    printf -v o '%%%02x' "'$char"
    RES+="$o"
  done

  LC_COLLATE=$COLLATE_BK
  echo $RES
}

cleanup() {
  echo "Check and cleanup after trap"
  mongosh \
    --quiet \
    --host "$MONGO_HOST" \
    --port "$MONGO_PORT" \
    --username "$MONGO_USER" \
    --password "$MONGO_PASS" \
    --authenticationDatabase "$MONGO_AUTHDB" \
    --file /scripts/cleanupLocks.js \
    -- "$MONGO_URI"
  rm $BACKUP_FULLPATH*
  exit 10
}
### FUNCTIONS DONE
###   (No more function declaration from this point)
################################################################################


################################################################################
### PARSING INPUT
#

# NOTE: This is GNU getopt. It is the default on Linux system.
#       But if you encounter an unknown error, this might be a thing to check.
TEMPOPT=$(getopt -n "$SCRIPT_LABEL" \
                 -o hvVu:p: \
                 -l help,host:,port:,version,verbose,username:,password:,authenticationDatabase:,backupPath:,backupName:,dataPath: \
                 -- "$@" \
         )

# If getopt return non-0 code, terminate this script
if [ $? != 0 ]; then
  ERROR=true verbose getopt "Terminating..."
  exit 1
fi

# Set parsed option to this script
eval set -- "$TEMPOPT"

# Get number of CPUs
CPUs=$(cat /proc/cpuinfo | grep processor | wc -l)
CPUs=$(expr $CPUs \* 3 + 3)
CPUs=$(expr $CPUs / 4)

# Set default value
VERBOSE=false
MONGO_AUTHDB="admin"
BACKUP_PATH="/fullbackup"
BACKUP_NAME="backup"
DATA_PATH="/data/db"

# Process options
while true; do
  case "$1" in
    -h | --help                   ) usage;              exit $?; ;;
         --host                   ) MONGO_HOST="$2";    shift 2; ;;
         --port                   ) MONGO_PORT="$2";    shift 2; ;;
    -V | --version                ) version;            exit $?; ;;
    -v | --verbose                ) VERBOSE=true;       shift 1; ;;
         --uri                    ) MONGO_URI="$2";     shift 2; ;;
    -u | --username               ) MONGO_USER="$2";    shift 2; ;;
    -p | --password               ) MONGO_PASS="$2";    shift 2; ;;
         --authenticationDatabase ) MONGO_AUTHDB="$2";  shift 2; ;;
         --backupPath             ) BACKUP_PATH="$2";   shift 2; ;;
         --backupName             ) BACKUP_NAME="$2";   shift 2; ;;
         --dataPath               ) DATA_PATH="$2";     shift 2; ;;
         --                       ) shift 1;            break;   ;;
         *                        ) exit 1;             break;   ;;
  esac
done
MONGO_URI="$1"

# Cook values
BACKUP_NAME+=-$(date -u "+%Y%m%d-%H%M00")
BACKUP_FULLPATH="$BACKUP_PATH/$BACKUP_NAME"

# Export some variables to use in child processes
export VERBOSE DATA_PATH BACKUP_FULLPATH

### PARSING INPUT
###   (Variable should be ready to be used at this point)
################################################################################


################################################################################
### VERIFICATION
#

# Verbose print variable
if [ "$VERBOSE" == true ]; then
  echo MONGO_URI="$MONGO_URI"
  echo MONGO_HOST="$MONGO_HOST"
  echo MONGO_PORT="$MONGO_PORT"
  echo MONGO_USER="$MONGO_USER"
  echo MONGO_PASS="<REDACTED>"
  echo MONGO_AUTHDB="$MONGO_AUTHDB"
  echo BACKUP_NAME="$BACKUP_NAME"
  echo BACKUP_PATH="$BACKUP_PATH"
  echo BACKUP_FULLPATH="$BACKUP_FULLPATH"
  echo DATA_PATH="$DATA_PATH"
fi

# Checking config before running backup
verbose assert "Check data path"
mongosh \
  --quiet \
  --host "$MONGO_HOST" \
  --port "$MONGO_PORT" \
  --username "$MONGO_USER" \
  --password "$MONGO_PASS" \
  --authenticationDatabase "$MONGO_AUTHDB" \
  --file /scripts/checkDataPath.js \
  -- "$MONGO_URI"
ASSERT_RESULT=$?
if [ "$ASSERT_RESULT" != 0 ]; then
  ERROR=true verbose assert "Check data path failed, exit $ASSERT_RESULT"
  exit $[10 + $ASSERT_RESULT]
fi

# Checking backup folder and data folder exists
verbose assert "Check data folder exists"
if [ ! -d "$DATA_PATH" ]; then
  ERROR=true verbose assert "Check data folder exists failed"
  exit 12;
fi

verbose assert "Check backup folder exists"
if [ ! -d "$BACKUP_PATH" ]; then
  ERROR=true verbose assert "Check backup folder exists failed"
  exit 13;
fi

# Checking if any other process are puting fsync on the database
verbose assert "Check fsync lock"
mongosh \
  --quiet \
  --host "$MONGO_HOST" \
  --port "$MONGO_PORT" \
  --username "$MONGO_USER" \
  --password "$MONGO_PASS" \
  --authenticationDatabase "$MONGO_AUTHDB" \
  --file /scripts/fsLockInfo.js \
  -- "$MONGO_URI"
ASSERT_RESULT=$?
if [ "$ASSERT_RESULT" != 0 ]; then
  ERROR=true verbose assert "Check fsync lock failed, there are $ASSERT_RESULT locks on the database"
  exit $[20 + $ASSERT_RESULT]
fi

verbose assert "All OK, continuing..."

### VERIFICATION
###   (Code after this point should not have variable related error)
################################################################################


################################################################################
### CLEANUP PREPARATION
#

# Trap exit signal
trap 'echo Process $$ terminated by SIGHUP;  cleanup' SIGHUP
trap 'echo Process $$ terminated by SIGINT;  cleanup' SIGINT
trap 'echo Process $$ terminated by SIGQUIT; cleanup' SIGQUIT
trap 'echo Process $$ terminated by SIGTERM; cleanup' SIGTERM

### CLEANUP PREPARATION
###   (Trap should catch all abnormal termination from this point)
################################################################################


################################################################################
### BACKUP PROCESS
#

INFO=true verbose main "Starting full backup process"
INFO=true verbose main "Backup process will use $CPUs cores"

verbose timestamp "Export backup timestamp"
mongosh \
  --quiet \
  --host "$MONGO_HOST" \
  --port "$MONGO_PORT" \
  --username "$MONGO_USER" \
  --password "$MONGO_PASS" \
  --authenticationDatabase "$MONGO_AUTHDB" \
  --file /scripts/captureTimestamp.js \
  -- "$MONGO_URI"
INFO=true verbose timestamp $(cat $BACKUP_FULLPATH.ts)

verbose lock "Starting locking process"
mongosh \
  --quiet \
  --host "$MONGO_HOST" \
  --port "$MONGO_PORT" \
  --username "$MONGO_USER" \
  --password "$MONGO_PASS" \
  --authenticationDatabase "$MONGO_AUTHDB" \
  --file /scripts/fsyncLock.js \
  -- "$MONGO_URI"
verbose lock "Finished locking process"

verbose lock "Verbose lock info"
mongosh \
  --quiet \
  --host "$MONGO_HOST" \
  --port "$MONGO_PORT" \
  --username "$MONGO_USER" \
  --password "$MONGO_PASS" \
  --authenticationDatabase "$MONGO_AUTHDB" \
  --file /scripts/fsLockVerify.js \
  -- "$MONGO_URI"
LOCKING_STATUS=$?
verbose lock "Verify locking status: $LOCKING_STATUS fsync locks granted"

verbose backup "Starting copying data files"
if [ "$VERBOSE" == true ]; then
  tar -I "zstd -k9T$CPUs" -cvvf "$BACKUP_FULLPATH.full.tar.zstd" "$DATA_PATH"
else
  tar -I "zstd -k9T$CPUs" -cf "$BACKUP_FULLPATH.full.tar.zstd" "$DATA_PATH"
fi
verbose backup "Finished copying data files"

verbose lock "Starting unlocking process"
mongosh \
  --quiet \
  --host "$MONGO_HOST" \
  --port "$MONGO_PORT" \
  --username "$MONGO_USER" \
  --password "$MONGO_PASS" \
  --authenticationDatabase "$MONGO_AUTHDB" \
  --file /scripts/fsyncUnlock.js \
  -- "$MONGO_URI"
verbose lock "Finished unlocking process"

verbose lock "Verify locking status"
mongosh \
  --quiet \
  --host "$MONGO_HOST" \
  --port "$MONGO_PORT" \
  --username "$MONGO_USER" \
  --password "$MONGO_PASS" \
  --authenticationDatabase "$MONGO_AUTHDB" \
  --file /scripts/fsLockVerify.js \
  -- "$MONGO_URI"
LOCKING_STATUS=$?
verbose lock "Verify locking status: $LOCKING_STATUS fsync locks remained"

INFO=true verbose main "Finished full backup process"

### BACKUP PROCESS
###   (It's done)
################################################################################
