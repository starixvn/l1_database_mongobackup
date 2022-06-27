#!/bin/bash

SCRIPT_VERSION=1.0.0
SCRIPT_LABEL=DIFFBACKUP

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
                 -l help,host:,port:,version,verbose,username:,password:,authenticationDatabase:,backupFull:,backupPath:,backupName: \
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
BACKUP_FULL="/fullbackup"
BACKUP_PATH="/diffbackup"
BACKUP_NAME="backup"
TMP_FOLDER="/tmp/mongodump"

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
         --backupFull             ) BACKUP_FULL="$2";   shift 2; ;;
         --backupPath             ) BACKUP_PATH="$2";   shift 2; ;;
         --backupName             ) BACKUP_NAME="$2";   shift 2; ;;
         --                       ) shift 1;            break;   ;;
         *                        ) exit 1;             break;   ;;
  esac
done
MONGO_URI="$1"

# Cook values
BACKUP_NAME+=-$(date -u "+%Y%m%d-%H%M00")
BACKUP_FULLPATH="$BACKUP_PATH/$BACKUP_NAME"

# Get timestamp for diff backup
TS_FULLFILE=$(ls -r $BACKUP_FULL/*.ts | head -1)
if [ ! -z "$TS_FULLFILE" ]; then
  TIMESTAMP_FULL=$(cat $TS_FULLFILE | tr -d '\r\n')
fi
TS_DIFFFILE=$(ls -r $BACKUP_PATH/*.ts | head -1)
if [ ! -z "$TS_DIFFFILE" ]; then
  TIMESTAMP_DIFF=$(cat $TS_DIFFFILE | tr -d '\r\n')
fi
TIMESTAMP=$TIMESTAMP_FULL
(( TIMESTAMP_DIFF > TIMESTAMP_FULL )) && TIMESTAMP=$TIMESTAMP_DIFF

# Verbose level
if [ "$VERBOSE" == true ]; then
  VERBOSE_LEVEL=5
else
  VERBOSE_LEVEL=0
fi

# Export some variables to use in child processes
export TIMESTAMP BACKUP_FULLPATH

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
  echo MONGO_PASS="$MONGO_PASS"
  echo MONGO_AUTHDB="$MONGO_AUTHDB"
  echo BACKUP_FULL="$BACKUP_FULL"
  echo BACKUP_PATH="$BACKUP_PATH"
  echo BACKUP_NAME="$BACKUP_NAME"
  echo BACKUP_FULLPATH="$BACKUP_FULLPATH"
  echo TS_FULLFILE="$TS_FULLFILE"
  echo TS_DIFFFILE="$TS_DIFFFILE"
  echo TIMESTAMP_FULL="$TIMESTAMP_FULL"
  echo TIMESTAMP_DIFF="$TIMESTAMP_DIFF"
  echo TIMESTAMP="$TIMESTAMP"
fi

verbose assert "Check backup folder exists"
if [ ! -d "$BACKUP_PATH" ]; then
  ERROR=true verbose assert "Check backup folder exists failed"
  exit 13;
fi
verbose assert "Check timestamp"
if [ -n "$TIMESTAMP" ] && [ "$TIMESTAMP" -eq "$TIMESTAMP" ] 2>/dev/null; then
  mongosh \
    --quiet \
    --host "$MONGO_HOST" \
    --port "$MONGO_PORT" \
    --username "$MONGO_USER" \
    --password "$MONGO_PASS" \
    --authenticationDatabase "$MONGO_AUTHDB" \
    --file /scripts/checkTimestamp.js \
    -- "$MONGO_URI"
  if [ "$?" != 0 ]; then
    ERROR=true verbose assert "Check timestamp failed, oplog is stalled. [$TIMESTAMP] < [$(cat /tmp/stallLimit)]"
    exit 21
  fi
else
  ERROR=true verbose assert "Timestamp is not number - [$TIMESTAMP]"
  exit 14
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

INFO=true verbose main "Starting diff backup process"
INFO=true verbose main "Backup process will use $CPUs cores"

verbose folder "Create temporary dumping folder"
mkdir /tmp/mongodump
verbose folder "Created temporary dumping folder"

INFO=true verbose timestamp $TIMESTAMP
(( TIMESTAMP == TIMESTAMP_FULL )) && cp $TS_FULLFILE $TMP_FOLDER
(( TIMESTAMP == TIMESTAMP_DIFF )) && cp $TS_DIFFFILE $TMP_FOLDER

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

verbose backup "Starting dumping oplog"
mongodump \
  --verbose=$VERBOSE_LEVEL \
  --host "$MONGO_HOST" \
  --port "$MONGO_PORT" \
  --username "$MONGO_USER" \
  --password "$MONGO_PASS" \
  --authenticationDatabase "$MONGO_AUTHDB" \
  --db "local" \
  --collection "oplog.rs" \
  --query "
{ \"\$and\": [
  {\"ts\": {\"\$gte\": {\"\$timestamp\": {\"t\": $TIMESTAMP, \"i\": 0}}}},
  {\"ns\": {\"\$not\": {\"\$regex\": \"_tmp(cuocs|ones)\$\"}}},
  {\"ns\": {\"\$not\": {\"\$regex\": \"system[.]profile\$\"}}}
]}" \
  --out $TMP_FOLDER \
  --uri "$MONGO_URI"
BACKUP_STATUS=$?
if [ "$BACKUP_STATUS" != 0 ]; then
  ERROR=true verbose assert "Error while dumping oplog, exit $BACKUP_STATUS"
  cleanup
  exit $[90 + $BACKUP_STATUS]
fi

verbose backup "Finished dumping oplog"

verbose backup "Compress oplog file"
if [ "$VERBOSE" == true ]; then
  tar -I "zstd -k9T$CPUs" -cvvf "$BACKUP_FULLPATH.diff.tar.zstd" -C "$TMP_FOLDER" .
else
  tar -I "zstd -k9T$CPUs" -cf "$BACKUP_FULLPATH.diff.tar.zstd" -C "$TMP_FOLDER" .
fi
verbose backup "Finished compressing oplog file"

INFO=true verbose main "Finished diff backup process"

### BACKUP PROCESS
###   (It's done)
################################################################################
