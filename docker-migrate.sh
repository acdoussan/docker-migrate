#!/bin/bash
#
# THIS SCRIPT IS PROVIDED AS IS. You assume all responsibility if things go wrong. Have a backup,
# assume the worst will happen, and consider it a happy accident if this script works.
#
# Based off of docker-volumes.sh by Ricardo Branco https://github.com/ricardobranco777/docker-volumes.sh
#
# Migrates a docker container from one host to another, including volume data and any options set on
# the container. The original container will be brought down as part of this process, but will be
# started back up after the required snapshots have been taken. It is recommended that you validate
# the new container before destroying the old one.
#
# This is primarily intended to be used for a isolated container that has been manually created, or
# that has data on it that can't be migrated in another way. If you have a complicated setup, or
# have a way to recreated the container and its data without migrating it, this script if probably
# not for you.
#
# IF YOUR CONTAINER HAS VOLUMES: Volumes are assumed to be external, you will have to create them on
# the new host before running this script.
#
# Example usege: ./docker-migrate.sh uptime-kuma root 10.0.0.0
# This example mill migrate the uptime-kuma container to host 10.0.0.0 using user root. It is
# recommended that you set up an SSH keypair, otherwise you will have to enter the password
# multiple times
#
# NOTES:
#  + We use the Ubuntu 18.04 Docker image with tar v1.29 that uses SEEK_DATA/SEEK_HOLE to manage sparse files.
#

if [[ $1 == "-v" || $1 == "--verbose" ]] ; then
    v="-v"
    shift
fi

if [[ $# -ne 3 ]] ; then
    echo "Usage: $0 [-v|--verbose] CONTAINER USER HOST" >&2
    exit 1
fi

IMAGE="ubuntu:18.04"

# Set DOCKER=podman if you want to use podman.io instead of docker
DOCKER=${DOCKER:-"docker"}

migrate_container() {
    echo "Local temp dir: $LOCAL_TMP"
    echo "Remote temp dir: $REMOTE_TMP"

    # Stop the container
    echo "Stopping container $CONTAINER"
    $DOCKER stop $CONTAINER

    # Create a new image
    $DOCKER inspect "$CONTAINER" > "$LOCAL_TMP/$CONTAINER.info"
    IMAGE_NAME=$($DOCKER run -i stedolan/jq < "$LOCAL_TMP/$CONTAINER.info" -r '.[0].Config.Image')

    echo "Creating image $IMAGE_NAME for container $CONTAINER"
    echo "$DOCKER commit $CONTAINER $IMAGE_NAME"
    $DOCKER commit $CONTAINER $IMAGE_NAME

    # Save and load image to another host
    echo "Saving image and loading it onto remote host, this may take a while, be patient"
    $DOCKER save $IMAGE_NAME | ssh $USER@$HOST $DOCKER load

    echo "Saving volumes"
    save_volumes

    echo "Saving container options"
    save_container_options

    # start container on local host
    echo "Restarting local container"
    $DOCKER start "$CONTAINER"

    # Copy volumes & compose to new host
    echo "Copying volumes and compose to remote host"
    scp $TAR_FILE_SRC $USER@$HOST:$TAR_FILE_DST
    scp $COMPOSE_FILE_SRC $USER@$HOST:$COMPOSE_FILE_DST

    # Create container with the same options used in the previous container
    echo "Creating container on remote host"
    ssh $USER@$HOST "$DOCKER compose -f $COMPOSE_FILE_DST create"

    # Load the volumes
    echo "Loading volumes on remote host"
    load_volumes

    # Start container on remote host
    echo "Staring remote container"
    ssh $USER@$HOST "$DOCKER start $CONTAINER"

    echo "$0 completed successfully"
}

save_container_options () {
    $DOCKER run --rm -v /var/run/docker.sock:/var/run/docker.sock ghcr.io/red5d/docker-autocompose "$CONTAINER" > "$COMPOSE_FILE_SRC"
}

get_volumes () {
    cat <($DOCKER inspect --type container -f '{{range .Mounts}}{{printf "%v\x00" .Destination}}{{end}}' "$CONTAINER" | head -c -1) | sort -uz
}

save_volumes () {
    if [ -f "$TAR_FILE_SRC" ] ; then
        echo "ERROR: $TAR_FILE_SRC already exists" >&2
        exit 1
    fi
    umask 077
    # Create a void tar file to avoid mounting its directory as a volume
    touch -- "$TAR_FILE_SRC"
    tmp_dir=$(mktemp -du -p /)
    get_volumes | $DOCKER run --rm -i --volumes-from "$CONTAINER" -e LC_ALL=C.UTF-8 -v "$TAR_FILE_SRC:/${tmp_dir}/${TAR_FILE_SRC##*/}" $IMAGE tar -c -a $v --null -T- -f "/${tmp_dir}/${TAR_FILE_SRC##*/}"
}

load_volumes () {
    tmp_dir=$(mktemp -du -p /)
    ssh $USER@$HOST "$DOCKER run --rm --volumes-from $CONTAINER -e LC_ALL=C.UTF-8 -v \"$TAR_FILE_DST:/${tmp_dir}/${TAR_FILE_DST##*/}\":ro $IMAGE tar -xp $v -S -f \"/${tmp_dir}/${TAR_FILE_DST##*/}\" -C / --overwrite"
}

CONTAINER="$1"
USER="$2"
HOST="$3"

LOCAL_TMP=$(mktemp -d)
REMOTE_TMP=$(ssh $USER@$HOST "mktemp -d")

TAR_FILE_NAME="$CONTAINER-volumes.tar.gz"
TAR_FILE_SRC=$(readlink -f "$LOCAL_TMP/$TAR_FILE_NAME")
TAR_FILE_DST="$REMOTE_TMP/$TAR_FILE_NAME"

COMPOSE_FILE_NAME="$CONTAINER.compose.yml"
COMPOSE_FILE_SRC="$LOCAL_TMP/$COMPOSE_FILE_NAME"
COMPOSE_FILE_DST="$REMOTE_TMP/$COMPOSE_FILE_NAME"

set -e
migrate_container
