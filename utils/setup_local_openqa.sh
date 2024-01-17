#!/bin/bash
#
# Helper script to start a local openQA instance.

set -e

CONTAINER_NAME="openqa-single-instance"
CONTAIMER_IMAGE_NAME="openqa:single-instance"
DOCKER="$(which podman)"
GNOME_NEEDLES_GIT_URL="https://gitlab.gnome.org/gnome/openqa-needles"
GNOME_TESTS_GIT_URL="https://gitlab.gnome.org/gnome/openqa-tests"
OPENQA_GIT_URL="https://github.com/os-autoinst/openqa"

if [ "$#" -lt 3 ]; then
    echo >&2 "Usage: $0 STATE_DIR ISO_PATH DISK_PATH [TESTS_REF]"
    exit 2
fi

STATE_DIR="$1"
ISO_PATH="$2"
DISK_PATH="$3"
TESTS_REF="${4:-master}"

set -u

check_no_container_exists() {
    local container_name=$1

    if $DOCKER inspect --type container "$container_name" &> /dev/null; then
        echo "Error: Container '$container_name' already exists. Remove it before continuing."
        exit 1
    fi
}

ensure_git_repo() {
    local repo_url=$1
    local repo_dir=$2

    if [ ! -d "$repo_dir" ]; then
        git clone "$repo_url" "$repo_dir"
    fi

    (cd "$repo_dir" && git pull origin master)
}

ensure_openqa_container_image() {
    local dockerfile_dir=$1
    (cd "$dockerfile_dir" && $DOCKER build . --tag openqa:single-instance)
}

ensure_test_media() {
    local state_dir="$1"
    local iso_path="$(readlink -f "$2")"
    local disk_path="$(readlink -f "$3")"
    local intermediate_iso_path="$1/installer.iso"
    local intermediate_disk_path="$1/disk.img"

    # After the container runs for the first time, these files will be owned by a random
    # UID and will not be writable by the user who runs the script.
    mkdir -p "${state_dir}/factory/iso"
    mkdir -p "${state_dir}/factory/hdd"
    if [ ! -e "$iso_path" ]; then ln -s "$intermediate_iso_path" "${state_dir}/factory/iso/installer.iso"; fi
    if [ ! -e "$disk_path" ]; then ln -s "$intermediate_disk_path" "${state_dir}/factory/hdd/disk.img"; fi

    # The intermediate links remain owned by the host user and we can update them.
    ln -sf "$iso_path" "$intermediate_iso_path"
    ln -sf "$disk_path" "$intermediate_disk_path"
}

create_and_start_container() {
   local container_name="$1"
   local container_image_name="$2"
   local state_dir="$3"

   # Published ports are:
   #
   #   80 (HTTP) for web UI access
   #   443 (HTTPS) for web UI access
   #   9526-9534: service ports as defined in openQA.git
   #   20013 (websocket) for web UI communication with isotovideo - used by “Developer mode”
   #
   podman run \
     --detach \
     --privileged \
     -v "$state_dir":/var/lib/openqa/share/ \
     --publish 8080:80 \
     --publish 8443:443 \
     --publish 9526-9534:9526-9534 \
     --publish 20013:20013 \
     --name "$container_name" \
     "$container_image_name"
}

wait_for_localhost_web_ui() {
    local timeout=30
    local end_time=$((SECONDS + timeout))

    echo "Waiting up to ${timeout} seconds for web UI to respond on <http://localhost:8080>."
    until [ $SECONDS -ge $end_time ]; do
        if [ "$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080)" = "200" ]; then
            echo "openQA web UI is responsive."
            return 0
        fi
        sleep 1
    done

    echo "Error: Timeout reached. Web UI did not respond within $timeout seconds."
    exit 1
}

main() {
    mkdir -p "$STATE_DIR"

    check_no_container_exists "$CONTAINER_NAME"
    ensure_git_repo "$OPENQA_GIT_URL" "${STATE_DIR}/openQA.git"
    ensure_openqa_container_image "${STATE_DIR}/openQA.git/container/single-instance"
    ensure_test_media "$STATE_DIR" "$ISO_PATH" "$DISK_PATH"
    create_and_start_container "$CONTAINER_NAME" "$CONTAIMER_IMAGE_NAME" "$STATE_DIR"

    wait_for_localhost_web_ui

    # Workaround a missing package in the container
    podman exec -i -t "$CONTAINER_NAME" zypper install -y qemu-hw-display-virtio-vga

    # Fetch tests and needles in the container
    #
    # First fix damage done by the bootstrapper that claims this repo for 'root', and any
    # previous branches which the fetchneedles script seems not to handle
    podman exec -i -t "$CONTAINER_NAME" chown -R geekotest:geekotest /var/lib/openqa/share/tests
    podman exec -i -t \
     --env=dist=gnomeos \
     --env=force=1 \
     --env=giturl="$GNOME_TESTS_GIT_URL" \
     --env=branch="$TESTS_REF" \
     --env=needles_giturl="${GNOME_NEEDLES_GIT_URL}#${TESTS_REF}" \
     "$CONTAINER_NAME" \
     /usr/share/openqa/script/fetchneedles

    echo "Local openQA instance running in container: ${CONTAINER_NAME}"
    echo
    echo "Open the web UI here: <http://localhost:8080/>"
    echo
    echo "Submit test jobs by running this in a clone of openqa-tests.git: "
    echo

    echo "    openqa-cli api \\"
    echo "      --apikey 1234567890ABCDEF \\"
    echo "      --apisecret 1234567890ABCDEF \\"
    echo "      --host http://localhost:8080 \\"
    echo "      -X POST isos \\"
    echo "      --param-file SCENARIO_DEFINITIONS_YAML=\"./config/scenario_definitions.yaml\" \\"
    echo "      ARCH=\"x86_64\"  \\"
    echo "      DISTRI=\"gnomeos\" \\"
    echo "      FLAVOR=\"iso\" \\"
    echo "      VERSION=master"
    echo
}

main
