# MongoDB Backup Solution

A comprehensive solution for MongoDB backup operations, providing containerized tools for full, differential, and disaster recovery backups.

## Overview

This project contains Docker images and scripts for performing different types of MongoDB backups:

- **Full Backup**: Complete database snapshots
- **Differential Backup**: Incremental backups capturing only changes since the last full backup
- **Disaster Recovery (DR) Backup**: Specialized backups with FTP upload and notification capabilities

The solution is built on top of MongoDB official tools, packaged in Docker containers for portability and ease of deployment.

## Components

### MongoDB Tools Base Image

The base image `mongotools` contains essential MongoDB utilities:

- MongoDB Shell (mongosh)
- MongoDB Database Tools (mongodump, mongorestore, etc.)

### Backup Solutions

Three specialized Docker images for different backup scenarios:

1. **mongobackupfull**: For complete MongoDB database backups
2. **mongobackupdiff**: For differential backups between full backups
3. **mongobackupdr**: For disaster recovery backups with external storage and notification support

## Usage

### Building Docker Images

Each solution component includes a `build_images.sh` script to build the respective Docker images:

```bash
# Build the MongoDB tools base image
cd mongotools.Dockerfile.d
./build_images.sh

# Build the backup solution images
cd ../mongobackups.Dockerfile.d
./build_images.sh
```

### Running Backups

#### Full Backup

```bash
docker run --rm \
  -v /path/to/backup/dir:/fullbackup \
  hub.lumigame.com/ldb/mongobackupfull:latest \
  ./FullBackup.sh \
  --host mongodb-host \
  --port 27017 \
  --username admin \
  --password password \
  --authenticationDatabase admin
```

#### Differential Backup

```bash
docker run --rm \
  -v /path/to/backup/dir:/diffbackup \
  hub.lumigame.com/ldb/mongobackupdiff:latest \
  ./DiffBackup.sh \
  --host mongodb-host \
  --port 27017 \
  --username admin \
  --password password \
  --authenticationDatabase admin
```

#### Disaster Recovery Backup

```bash
docker run --rm \
  -v /path/to/backup/dir:/drbackup \
  -v /path/to/gnupg:/gnupg \
  hub.lumigame.com/ldb/mongobackupdr:latest \
  ./DRBackup.sh \
  --host mongodb-host \
  --port 27017 \
  --username admin \
  --password password \
  --authenticationDatabase admin \
  --ftpHost ftp-server \
  --ftpUser ftpuser \
  --ftpPass ftppassword \
  --botKey telegram-bot-key \
  --roomId telegram-chat-id
```

## Features

- **Automated Backup Scripts**: Well-structured shell scripts for different backup strategies
- **Containerized Solution**: Portable and isolated environment for consistent backup operations
- **FTP Integration**: Upload backups to remote FTP servers for offsite storage
- **Notification System**: Telegram integration for backup status notifications
- **Volume Mounting**: Easy data persistence through Docker volumes

## Requirements

- Docker
- MongoDB instance
- Storage space for backups
- (Optional) FTP server for DR backups
- (Optional) Telegram bot for notifications

## License

This project is proprietary software for internal use.

## Authors

- Billy Bui (billy.bui@luminet.vn)
