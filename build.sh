#!/bin/bash

errchk() {
    if [ "$1" != "0" ] ; then
	echo "$2"
	echo "Exiting."
	exit 1
    fi
}

# ***** Configuration *****
# Assign configuration values here or set environment variables before calling script.
local_repo_path="$BAKERY_LOCAL_REPO_PATH"
remote_repo_path="$BAKERY_REMOTE_REPO_PATH"
repo_name="spigot_we_minecraft"

# Some options may be edited directly in the Dockerfile.master.

if [ -z "$local_repo_path" ] || [ -z "$remote_repo_path" ] ; then
    errchk 1 'Configuration variables in script not set. Assign values in script or set corresponding environment variables.'
fi


APP_VERSION=$1
image_tag=$APP_VERSION

# The project directory is the folder containing this script.
project_dir=$( dirname "$0" )
project_dir=$( ( cd "$project_dir" && pwd ) )
echo "Project directory is ${project_dir}."
if [ -z "$project_dir" ] ; then
    errck 1 "Error: Could not determine project_dir."
fi

if [ -n "$image_tag" ] ; then
    local_repo_tag="${local_repo_path}/${repo_name}:${image_tag}"
    remote_repo_tag="${remote_repo_path}/${repo_name}:${image_tag}"    
else
    local_repo_tag="${local_repo_path}:${repo_name}"
    remote_repo_tag="${remote_repo_path}:${repo_name}"
fi

# Prepare rootfs.
# jar_file=minecraft_server.${APP_VERSION}.jar
worldedit_jar="${project_dir}/$2"
worldguard_jar="${project_dir}/$3"

if [ ! -f "$worldedit_jar" -o ! -f "$worldguard_jar" ] ; then
    echo "usage: $(basename $0) <mc version> <name of worldedit jar> <name of worldguard jar>"
    exit 1
fi

rootfs="${project_dir}/rootfs"
echo "Cleaning up rootfs from previous build."
rm -frd "$rootfs"

plugins_dir="${rootfs}/opt/mc/server/plugins"
mkdir -p "${plugins_dir}"

chmod +x "${worldedit_jar}"
chmod +x "${worldguard_jar}"

cp "${worldedit_jar}" "${plugins_dir}"
cp "${worldguard_jar}" "${plugins_dir}"

# Create and copy config files?

# Rewrite base image tag in Dockerfile. (ARG Variables support in FROM starting in docker v17.)
echo '# This file is automatically created from Dockerfile.master. DO NOT EDIT! EDIT Dockerfile.master!' > "${project_dir}/Dockerfile"
sed "1 s/SED_REPLACE_TAG_APP_VERSION/${APP_VERSION}/" "${project_dir}/Dockerfile.master" >> "${project_dir}/Dockerfile"

# Build.
echo "Building $local_repo_tag"
APP_VERSION="${APP_VERSION}" docker build "${project_dir}" -t "${local_repo_tag}"
errchk $? 'Docker build failed.'

# Get image id.
image_id=$(docker images -q "${local_repo_tag}")

test -n $image_id
errchk $? 'Could not retrieve docker image id.'
echo "Image id is ${image_id}."

# Tag for Upload to aws repo.
echo "Re-tagging image for upload to remote repository."
docker tag "${image_id}" "${remote_repo_tag}"
errchk $? "Failed re-tagging image ${image_id}".

# Upload.
echo "Execute the following commands to upload the image to remote aws repository."
echo '   $(aws ecr get-login --no-include-email --region eu-central-1)'
echo "   docker push ${remote_repo_tag}"
