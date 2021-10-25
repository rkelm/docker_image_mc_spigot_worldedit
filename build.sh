#!/bin/bash

# ***** Configuration *****
# Assign configuration values here or set environment variables before calling script.
local_repo_path="$BAKERY_LOCAL_REPO_PATH"
remote_repo_path="$BAKERY_REMOTE_REPO_PATH"
repo_name="minecraft_spigot_worldedit"

# Some options may be edited directly in the Dockerfile.master.

# ***** Functions *****
errchk() {
    if [ "$1" != "0" ] ; then
	echo "$2"
	echo "Exiting."
	exit 1
    fi
}

# ***** Initialization *****

if [ -z "$local_repo_path" ] || [ -z "$remote_repo_path" ] ; then
    errchk 1 'Configuration variables in script not set. Assign values in script or set corresponding environment variables.'
fi

app_version=$1
image_tag=$app_version

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
# jar_file=minecraft_server.${app_version}.jar
worldedit_jar="${project_dir}/$2"
worldguard_jar="${project_dir}/$3"
vault_jar="${project_dir}/$4"
permissions_jar="${project_dir}/$5"


if [ ! -f "$worldedit_jar" -o ! -f "$worldguard_jar" -o ! -f "$vault_jar" -o ! -f "$permissions_jar" ] ; then
    echo "usage: $(basename $0) <mc version> <name of worldedit jar> <.. worldguard jar> <.. vault jar> <.. permissions jar>"
    exit 1
fi

rootfs="${project_dir}/rootfs"
echo "Cleaning up rootfs from previous build."
rm -frd "$rootfs"

plugins_dir="${rootfs}/opt/mc/plugins_jar"
mkdir -p "${plugins_dir}"

chmod +x "${worldedit_jar}"
chmod +x "${worldguard_jar}"
chmod +x "${vault_jar}"
chmod +x "${permissions_jar}"

cp "${worldedit_jar}" "${plugins_dir}"
cp "${worldguard_jar}" "${plugins_dir}"
cp "${vault_jar}" "${plugins_dir}"
cp "${permissions_jar}" "${plugins_dir}"

# Create and copy config files?

# Rewrite base image tag in Dockerfile. (ARG Variables support in FROM starting in docker v17.)
#echo '# This file is automatically created from Dockerfile.master. DO NOT EDIT! EDIT Dockerfile.master!' > "${project_dir}/Dockerfile"
#sed "1 s/SED_REPLACE_TAG_APP_VERSION/${app_version}/" "${project_dir}/Dockerfile.master" >> "${project_dir}/Dockerfile"

# Build.
echo "Building $local_repo_tag"
docker build "${project_dir}" --no-cache --build-arg APP_VERSION="${app_version}" -t "${local_repo_tag}"
errchk $? 'Docker build failed.'

# Get image id.
image_id=$(docker images -q "${local_repo_tag}")

test -n $image_id
errchk $? 'Could not retrieve docker image id.'
echo "Image id is ${image_id}."

# ***** Test image *****
echo "***** Testing image *****"
"${project_dir}/test/test_simple_run.sh" "${local_repo_path}/${repo_name}:${image_tag}"
errchk $? "Test failed."

# Tag for Upload to aws repo.
if [ ! -z "$BAKERY_REMOTE_REPO_PATH" ] ; then
    echo "Re-tagging image for upload to remote repository."
    docker tag "${image_id}" "${remote_repo_path}/${repo_name}:${image_tag}"
    errchk $? "Failed re-tagging image ${image_id}."
else
    echo "Environment variable BAKERY_REMOTE_REPO_PATH not set. Skipping retagging image."
fi

# Upload image if necessary env vars are set.
if [ ! -z "$BAKERY_REMOTE_REPO_PATH" ] && [ ! -z "$AWS_ACCESS_KEY_ID" ] && [ ! -z "$AWS_SECRET_ACCESS_KEY" ] && \
       [ ! -z "$AWS_DEFAULT_REGION" ] ; then
    echo "Logging in to aws account."
    $(aws ecr get-login --no-include-email --region eu-central-1)
    echo "Pushing ${remote_repo_path}/${repo_name}:${image_tag} to remote repository."
    docker push "${remote_repo_path}/${repo_name}:${image_tag}"
else
    echo "Execute the following commands to upload the image to remote aws repository."
    echo '   $(aws ecr get-login --no-include-email --region eu-central-1)'
    echo "   docker push ${remote_repo_path}/${repo_name}:${image_tag}"
fi
