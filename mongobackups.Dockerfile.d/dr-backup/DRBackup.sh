#!/bin/bash

SCRIPT_VERSION=2.0.3
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
        --ftpHost                 The FTP host
        --ftpPort                 The FTP port
        --ftpUser                 The username to connect to FTP server
        --ftpPass                 The password to connect to FTP server
        --botKey                  The API key of Telegram bot
        --roomId                  The Telegram chat id
        --patchFolder             The sub-folder name for storing patches

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

notify() {
  if [ -z $BOT_API_KEY ]; then
    ERROR=true verbose telegram "No BOT_API_KEY provided. Returning..."
    return -1
  fi

  local CHAT_ID=$1
  local MESSAGE=$2

  if [ -z $CHAT_ID ]; then
    ERROR=true verbose telegram "No CHAT_ID provided. Returning..."
    return -2
  fi

  if [ -z $MESSAGE ]; then
    ERROR=true verbose telegram "No MESSAGE provided. Returning..."
    return -3
  fi

  curl "https://api.telegram.org/bot$BOT_API_KEY/sendMessage" \
    --data-urlencode "parse_mode=MarkdownV2" \
    --data-urlencode "chat_id=$CHAT_ID" \
    --data-urlencode "message=[$SCRIPT_LABEL:$SCRIPT_VERSION] $PATCH_FOLDER #$MONGO_PORT\n$MESSAGE"

  verbose telegram "Successfully sent message to $CHAT_ID"
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
                 -l help,host:,port:,version,verbose,username:,password:,authenticationDatabase:,backupPath:,ftpHost:,ftpPort:,ftpUser:,ftpPass:,botKey:,roomId:,patchFolder: \
                 -- "$@" \
         )

# If getopt return non-0 code, terminate this script
if [ $? != 0 ]; then
  ERROR=true verbose getopt "Terminating..."
  notify $NOTI_ROOM "(1) Failed to parse script parameters"
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
PATCH_PATH="/tmp/patch"
FTP_OUTPUT="/tmp/ftp-output.log"
SQUASH_LIMIT=72
NOTI_ROOM=925798134
PATCH_FOLDER=

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
         --ftpHost                ) FTP_HOST="$2";      shift 2; ;;
         --ftpPort                ) FTP_PORT="$2";      shift 2; ;;
         --ftpUser                ) FTP_USER="$2";      shift 2; ;;
         --ftpPass                ) FTP_PASS="$2";      shift 2; ;;
         --botKey                 ) BOT_API_KEY="$2";   shift 2; ;;
         --roomId                 ) NOTI_ROOM="$2";     shift 2; ;;
         --patchFolder            ) PATCH_FOLDER="$2";  shift 2; ;;
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
  echo PATCH_PATH="$PATCH_PATH"
  echo PATCH_FOLDER="$PATCH_FOLDER"
  echo FTP_HOST="$FTP_HOST"
  echo FTP_PORT="$FTP_PORT"
  echo FTP_USER="$FTP_USER"
  echo FTP_PASS="<REDACTED>"
  echo BOT_API_KEY="<REDACTED>"
  echo NOTI_ROOM="$NOTI_ROOM"
fi

verbose assert "Checking backup folder exists"
if [ ! -d "$BACKUP_PATH" ]; then
  ERROR=true verbose assert "  Backup folder does not exists"
  notify $NOTI_ROOM "(13) Backup folder does not exists"
  exit 13
fi

# Checking server status
verbose ftp "Running ftp assert sequences"
{ pftp -vin $FTP_HOST $FTP_PORT >$FTP_OUTPUT 2>&1 ; } <<EOF
user $FTP_USER $FTP_PASS
binary
cd /LUM
mkdir /LUM/init
!touch /tmp/assert
put /tmp/assert /LUM/init/assert
get /LUM/init/assert /tmp/assert-get
del /LUM/init/assert
rmdir /LUM/init
!rm /tmp/assert*
bye
EOF

# Check if connection timed out
verbose ftp "Checking ftp connection"
if { grep "timed out" $FTP_OUTPUT; }; then
  ERROR=true verbose assert "  FTP connection timed out"
  notify $NOTI_ROOM "(408) FTP connection timed out"
  exit 408
fi

# Check if authentication failed
verbose ftp "Checking ftp authentication"
if { grep "^[45]3" $FTP_OUTPUT; }; then
  ERROR=true verbose assert "  FTP authentication failed"
  notify $NOTI_ROOM "(530) FTP authentication failed"
  exit 530
fi

# Check for other errors
verbose ftp "Checking ftp errors"
if { grep "^[45]" $FTP_OUTPUT; }; then
  ERROR=true verbose assert "  FTP error occurs"
  notify $NOTI_ROOM "(500) FTP error occurs"
  exit 500
fi

verbose git "Checking git folder status"
cd $BACKUP_PATH
git status >/dev/null 2>&1
GIT_STATUS=$?
if [ "$GIT_STATUS" != 0 ]; then
  if [ ! -z "$(ls -A)" ]; then
    ERROR=true verbose assert "  Backup folder is not git folder and is not empty"
    notify $NOTI_ROOM "(14) Backup folder is not git folder and is not empty"
    exit 14
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
  verbose git "Starting initiating git repository"
  git init
  GIT_STATUS=$?
  if [ "$GIT_STATUS" != 0 ]; then
    ERROR=true verbose assert "  Failed to initiate git repository"
    notify $NOTI_ROOM "($GIT_STATUS) Failed to initiate git repository"
    exit $GIT_STATUS
  fi
  verbose git "Finished initiating git repository"
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
      --out "$BACKUP_PATH" \
      --uri "$MONGO_URI"
    BACKUP_STATUS=$?
    if [ "$BACKUP_STATUS" != 0 ]; then
      ERROR=true verbose assert "  - Error while dumping $DB.$COLL, returned $BACKUP_STATUS"
      notify $NOTI_ROOM "($BACKUP_STATUS) Error while dumping $DB.$COLL"
    fi
  done
  verbose dump "- Finished processing database [${DB}]..."
done
verbose backup "Finished dumping collections"

verbose git "Starting commiting new changes"
git add .
git commit -m "Backup at $(date -u "+%Y-%m-%d %H:%M")" -S
if [ "$(git log --oneline | wc -l)" -gt "$SQUASH_LIMIT" ]; then
  verbose git "Limitting number of commit, squashing..."
  git checkout --orphan squash-main main
  git commit -m "Squash at $(date -u "+%Y-%m-%d %H:%M")"
  git branch -M squash-main main
fi
git gc --prune=now
verbose git "Finished commiting new changes"

verbose patch "Starting patching procedure"
verbose patch "  Create patch for latest commit"
mkdir $PATCH_PATH -p

# If HEAD has no previous commit, HEAD is a squashed commit
git rev-parse HEAD^ >/dev/null 2>&1
SQUASHED=$?
if [ "$SQUASHED" != 0 ]; then
  # If squashed, there are only commit in the tree, HEAD^ will cause git to fail
  git format-patch --output-directory $PATCH_PATH HEAD HEAD
else
  # Generate patch for latest commit only
  git format-patch --output-directory $PATCH_PATH ^HEAD^ HEAD
fi

verbose patch "  Encrypt patch file"
# gpg only accept one file at a time, so we fetch only 1 file to proceed (in theory there will be only 1 file)
PATCH_NAME=$( ls "$PATCH_PATH/*.patch" -t | head -1 )
gpg --encrypt --recipient dr@luminet.vn $PATCH_NAME

verbose patch "  Send patch to ftp"
{ pftp -vin $FTP_HOST $FTP_PORT >$FTP_OUTPUT 2>&1 ; } <<EOF
user $FTP_USER $FTP_PASS
binary
mkdir /LUM/patches
mkdir /LUM/patches/$PATCH_FOLDER
cd /LUM/patches/$PATCH_FOLDER
put $PATCH_NAME.gpg
bye
EOF

verbose patch "  Send telegram message"
notify $NOTI_ROOM "Successfully pushed $PATCH_FOLDER/$PATCH_NAME.gpg to ftp server"

verbose patch "Finished patching procedure"

INFO=true verbose main "Finished dr backup process"

### BACKUP PROCESS
###   (It's done)
################################################################################
