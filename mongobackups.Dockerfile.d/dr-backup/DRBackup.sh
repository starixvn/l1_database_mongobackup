#!/bin/bash

SCRIPT_VERSION=1.0.0
SCRIPT_LABEL=DRBACKUP

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
        --gitRepo                 The repository where to save dr data
        --gitToken                The token to access git repository

    [to be updated]
  " 1>&2
  exit 2
}

# Version function
version() {
  echo "$SCRIPT_LABEL version: $SCRIPT_VERSION" 1>&2
  echo "---" 1>&2
  mongodump --version
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
  git reset --hard
  git clean -fd
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
                 -l help,host:,port:,version,verbose,username:,password:,authenticationDatabase:,backupPath:,gitRepo:,gitToken: \
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
BACKUP_PATH="/drbackup"

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
         --gitRepo                ) GIT_REPO="$2";      shift 2; ;;
         --gitToken               ) GIT_TOKEN="$2";     shift 2; ;;
         --                       ) shift 1;            break;   ;;
         *                        ) exit 1;             break;   ;;
  esac
done
MONGO_URI="$1"

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
  echo MONGO_PASS="<REDACTED>"
  echo MONGO_AUTHDB="$MONGO_AUTHDB"
  echo BACKUP_PATH="$BACKUP_PATH"
  echo GIT_REPO="$GIT_REPO"
  echo GIT_TOKEN="<REDACTED>"
fi

verbose assert "Checking backup folder exists"
if [ ! -d "$BACKUP_PATH" ]; then
  ERROR=true verbose assert "  Backup folder does not exists"
  exit 13
fi

verbose git "Checking git folder status"
cd $BACKUP_PATH
git status >/dev/null 2>&1
GIT_STATUS=$?
if [ "$GIT_STATUS" != 0 ]; then
  if [ ! -z "$(ls -A)" ]; then
    ERROR=true verbose assert "  Backup folder is not git folder and is not empty"
    exit 14
  fi
else
  GIT_REMOTE=$(git remote get-url origin)
  if [ "${GIT_REMOTE/\:\/\/*\:*@/://}" != "$GIT_REPO" ]; then
    ERROR=true verbose assert "  Git repository does not match. Abort to avoid incorrect data changes."
    exit 15
  fi
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

INFO=true verbose main "Starting dr backup process"

if [ "$GIT_STATUS" != 0 ]; then
  verbose git "Starting cloning git repository"
  git clone ${GIT_REPO/\:\/\//://oauth2:${GIT_TOKEN}@} .
  GIT_STATUS=$?
  if [ "$GIT_STATUS" != 0 ]; then
    ERROR=true verbose assert "  Failed to clone git repository"
    exit $GIT_STATUS
  fi
  verbose git "Finished cloning git repository"
else
  verbose git "Starting cleaning git repository"
  git reset --hard
  git clean -fd
  verbose git "Finished cleaning git repository"
fi

verbose backup "Starting dumping collections"
for DB in $(ls -1 /dbs/)
do
  verbose dump "- Starting processing database [${DB}]..."
  for COLL in $(cat /dbs/${DB})
  do
    mongodump \
      --verbose=$VERBOSE_LEVEL \
      --host "$MONGO_HOST" \
      --port "$MONGO_PORT" \
      --username "$MONGO_USER" \
      --password "$MONGO_PASS" \
      --authenticationDatabase "$MONGO_AUTHDB" \
      --db "$DB" \
      --collection "$COLL" \
      --out $BACKUP_PATH \
      --uri "$MONGO_URI"
    BACKUP_STATUS=$?
    if [ "$BACKUP_STATUS" != 0 ]; then
      ERROR=true verbose assert "  - Error while dumping $DB.$COLL, returned $BACKUP_STATUS"
    fi
  done
  verbose dump "- Finished processing database [${DB}]..."
done
verbose backup "Finished dumping collections"

verbose git "Starting commiting new changes"
git add .
git commit -m "Backup at $(date -u "+%Y-%m-%d %H:%M")" -S
git push
verbose git "Finished commiting new changes"

INFO=true verbose main "Finished dr backup process"

### BACKUP PROCESS
###   (It's done)
################################################################################
