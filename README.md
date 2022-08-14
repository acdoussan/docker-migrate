# docker-migrate
Based off of docker-volumes.sh by Ricardo Branco https://github.com/ricardobranco777/docker-volumes.sh

THIS SCRIPT IS PROVIDED AS IS. You assume all responsibility if things go wrong. Have a backup,
assume the worst will happen, and consider it a happy accident if this script works.

Migrates a docker container from one host to another, including volume data and any options set on
the container. The original container will be brought down as part of this process, but will be
started back up after the required snapshots have been taken. It is recommended that you validate
the new container before destroying the old one.

This is primarily intended to be used for a isolated container that has been manually created, or
that has data on it that can't be migrated in another way. If you have a complicated setup, or
have a way to recreated the container and its data without migrating it, this script if probably
not for you.

IF YOUR CONTAINER HAS VOLUMES: Volumes are assumed to be external, you will have to create them on
the new host before running this script.

# Requirements
Docker must already be installed on both the local and remote host.

If your host does not have internet access, `ubuntu:18.04` must be available on the local and remote host, and `stedolan/jq` must be available on the local host.

# Usage

`./docker-migrate.sh [-v|--verbose] <CONTAINER> <USER> <HOST>`

Ex: `./docker-migrate.sh uptime-kuma root 10.0.0.0`

This example mill migrate the uptime-kuma container to host 10.0.0.0 using user root. It is
recommended that you set up an SSH keypair, otherwise you will have to enter the password
multiple times.

# Podman

NOTE: This is untested, but I have left it in based off of the docker-volumes.sh script

To use [Podman](https://podman.io) instead of Docker, prepend `DOCKER=podman` to the command line to set the `DOCKER` environment variable.

# Notes
* This script could have been written in Python or Go, but the tarfile module and the tar package lack support for writing sparse files.
* We use the Ubuntu 18.04 Docker image with GNU tar v1.29 that uses **SEEK\_DATA**/**SEEK\_HOLE** to [manage sparse files](https://www.gnu.org/software/tar/manual/html_chapter/tar_8.html#SEC137).
* To see the volumes that would be processed run `docker container inspect -f '{{json .Mounts}}' $CONTAINER` and pipe it to either [`jq`](https://stedolan.github.io/jq/) or `python -m json.tool`.

# Bugs / Features
* Make sure the volumes are defined as such with the `VOLUME` directive. For example, the Apache image lacks them, but you can add them manually with `docker commit --change 'VOLUME /usr/local/apache2/htdocs' $CONTAINER $CONTAINER`
