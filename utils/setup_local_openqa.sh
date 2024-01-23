#!/bin/bash
#
# Helper script to start a local openQA instance.

set -e

DOCKER="$(which podman)"
GNOME_NEEDLES_GIT_URL="https://gitlab.gnome.org/GNOME/openqa-needles"
GNOME_TESTS_GIT_URL="https://gitlab.gnome.org/GNOME/openqa-tests"
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

container_exists() {
    local container_name=$1

    if $DOCKER inspect --type container "$container_name" &> /dev/null; then
        return 0  # 0 means true
    else
        return 1  # 1 means false
    fi
}

container_image_exists() {
    local container_image_name=$1

    if $DOCKER inspect --type image "$container_image_name" &> /dev/null; then
        return 0  # 0 means true
    else
        return 1  # 1 means false
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

ensure_base_container_image() {
    local dockerfile_dir=$1
    local base_image_name="$2"
    (cd "$dockerfile_dir" && $DOCKER build . --tag "$base_image_name")
}

wait_for_localhost_web_ui() {
    local timeout="$1"
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

ensure_bootstrapped_container() {
    local container_name="$1"
    local base_container_image_name="$2"
    local bootstrapped_container_image_name="$3"
    local state_dir="$4"

    if container_image_exists "$bootstrapped_container_image_name"; then
        echo "Bootstrapped container image '$bootstrapped_container_image_name' exists, reusing it."
        return 0
    fi

    # Published ports are:
    #
    #   80 (HTTP) for web UI access
    #
    podman run \
      --detach \
      --privileged \
      -v "$state_dir":/var/lib/openqa/share/ \
      --publish 8080:80 \
      --name "$container_name" \
      "$base_container_image_name"

     # When the web UI appears, the bootstrap process is complete.
     #
     # One minute timeout as this fetches packages from the internet, which
     # can take a while depending on local download speed.
     wait_for_localhost_web_ui 60

     # Workaround a missing package in the container
     podman exec -i -t "$container_name" zypper install -y qemu-hw-display-virtio-vga

     # Hack so config/smbios.txt from openqa-tests.git is available in a well-known path.
     podman exec "$container_name" ln -sf /var/lib/openqa/share/tests/gnomeos/ /tests

     # Work around https://progress.opensuse.org/issues/153499
     podman exec "$container_name" sed -e "s/if (port !== 80 || port !== 443)/if (port !== 80 || port !== 8080 || port !== 443)/" -i ./usr/share/openqa/assets/javascripts/openqa.js

     # Save bootstrapped container state as an image and remove container.
     podman commit "$container_name" "$bootstrapped_container_image_name"
     podman kill "$container_name"
     podman rm "$container_name"
}

create_and_run_container() {
    local container_name="$1"
    local bootstrapped_container_image_name="$2"
    local state_dir="$3"
    local iso_path="$4"
    local disk_path="$5"

    # Published ports are:
    #
    #   80 (HTTP) for web UI access (as host port 8080)
    #   9526-9534: service ports as defined in openQA.git
    #   20013 (websocket) for web UI communication with isotovideo - used by “Developer mode”
    #
    podman run \
      --detach \
      --privileged \
      -v "$state_dir":/var/lib/openqa/share/ \
      -v "$iso_path":/var/lib/openqa/share/factory/iso/installer.iso \
      -v "$disk_path":/var/lib/openqa/share/factory/hdd/disk.img \
      --publish 8080:80 \
      --publish 9526-9534:9526-9534 \
      --publish 20013:20013 \
      --name "$container_name" \
      "$bootstrapped_container_image_name"

    # This should appear quickly as the bootstrap script doesn't need to do any work.
    wait_for_localhost_web_ui 10
}

main() {
    local container_name="openqa-single-instance"
    local base_container_image_name="openqa:single-instance-base"
    local bootstrapped_container_image_name="openqa:single-instance-bootstrapped"

    mkdir -p "$STATE_DIR"

    if container_exists "$container_name"; then
        echo "Error: Container '$container_name' already exists. Remove it before continuing."
        exit 1
    fi

    ensure_git_repo "$OPENQA_GIT_URL" "${STATE_DIR}/openQA.git"
    ensure_base_container_image "${STATE_DIR}/openQA.git/container/single-instance" "$base_container_image_name"
    ensure_bootstrapped_container "$container_name" "$base_container_image_name" "$bootstrapped_container_image_name" "$STATE_DIR"

    create_and_run_container "$container_name" "$bootstrapped_container_image_name" "$STATE_DIR" "$ISO_PATH" "$DISK_PATH"

    # Work around potential bad repo ownership (seemingly caused by bootstrap script)
    local container_tests_path="/var/lib/openqa/share/tests/gnomeos"
    podman exec -i -t "$container_name" chown -R geekotest:geekotest "$(dirname "$container_tests_path")"
    # Work around potential in-progress rebase (seemingly caused by fetchneedles script failing when branch changes).
    podman exec -i -t -u geekotest "$container_name" bash -c \
        "if [ -e \"${container_tests_path}/.git/rebase-merge\" ]; then git -C \"${container_tests_path}\" rebase --abort; fi"
    podman exec -i -t -u geekotest "$container_name" bash -c \
        "if [ -e \"${container_tests_path}/needles/.git/rebase-merge\" ]; then git -C \"${container_tests_path}/needles\" rebase --abort; fi"
    # Change branch since fetchneedles script may not do it.
    # Clean tree first to avoid "untracked files" issues.
    podman exec -i -t -u geekotest "$container_name" bash -c \
        "git -C \"${container_tests_path}\" clean -dfx; git -C \"${container_tests_path}\" checkout $TESTS_REF;"
    podman exec -i -t -u geekotest "$container_name" bash -c \
        "git -C \"${container_tests_path}/needles\" clean -dfx; git -C \"${container_tests_path}/needles\" checkout $TESTS_REF;"

    # Fetch tests and needles in the container
    podman exec -i -t -u geekotest \
     --env=dist=gnomeos \
     --env=force=1 \
     --env=giturl="$GNOME_TESTS_GIT_URL" \
     --env=branch="$TESTS_REF" \
     --env=needles_giturl="${GNOME_NEEDLES_GIT_URL}#${TESTS_REF}" \
     "$container_name" \
     /usr/share/openqa/script/fetchneedles

    echo "Local openQA instance running in container: ${container_name}"
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
