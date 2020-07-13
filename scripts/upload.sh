#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# -----------------------------------------------------------------------------
# Helm variables helpers. These functions need the following variables:
#
#    HELM_VERSION    -  The helm version to use, default is 3.1.1.
#    IMAGE_SUFFIX    -  The suffix for k3s image, default is k3s1, ref to: https://hub.docker.com/r/rancher/k3s/tags.

HELM_VERSION=${HELM_VERSION:-"v3.1.1"}
HELM_REPO_PATH=${HELM_REPO_PATH:-"http://charts.cnrancher.cn/octopus-catalog"}
HELM_REPO_NAME=${HELM_REPO_NAME:-"octopus-catalogtt"}
HELM_REPO_USERNAME=${HELM_REPO_USERNAME:-""}
HELM_REPO_PASSWORD=${HELM_REPO_PASSWORD:-""}

cd $(dirname $0)/../charts/

function octopus::helm::install() {
  local version=${HELM_VERSION:-"v3.1.1"}
  # e.g https://get.helm.sh/helm-v3.1.1-linux-amd64.tar.gz
  curl -fL "https://get.helm.sh/helm-${version}-$(octopus::util::get_os)-$(octopus::util::get_arch).tar.gz" -o /tmp/helm
  chmod +x /tmp/helm && mv /tmp/helm /usr/local/bin/helm
}

function octopus::helm::validate() {
  if [[ -n "$(command -v helm)" ]]; then
    return 0
  fi

  octopus::log::info "installing k3d"
  if octopus::helm::install; then
    octopus::log::info "$(helm --version 2>&1)"
    return 0
  fi
  octopus::log::error "no k3d available"
  return 1
}

function octopus::helm::start() {
  if ! octopus::helm::validate; then
    octopus::log::fatal "helm hasn't been installed"
  fi
  if ! octopus::helm::plugin; then
    octopus::log::fatal "failed to install helm plugin"
  fi
  if ! octopus::helm::repo; then
    octopus::log::fatal "failed to add helm repo ${HELM_REPO_PATH}"
  fi

  octopus::charts::package
  octopus::charts::upload
}

# Info level logging.
function octopus::log::info() {
  local message="${2:-}"
  local timestamp
  timestamp="$(date +"[%m%d %H:%M:%S]")"
  echo -e "\033[34m[INFO]\033[0m ${timestamp} ${1-}"
  shift 1
  for message; do
    echo -e "${message}"
  done
}

# Error level logging, log an error but keep going, don't dump the stack or exit.
function octopus::log::error() {
  local message="${1:-}"

  local timestamp
  timestamp="$(date +"[%m%d %H:%M:%S]")"
  echo "\033[31m[ERRO]\033[0m ${timestamp} ${1-}" >&2
  shift 1
  for message; do
    echo -e "${message}" >&2
  done
}

# Fatal level logging, log an error but exit with 1, don't dump the stack or exit.
function octopus::log::fatal() {
  local message="${1:-}"

  local timestamp
  timestamp="$(date +"[%m%d %H:%M:%S]")"
  echo -e "\033[41;33m[FATA]\033[0m ${timestamp} ${1-}" >&2
  shift 1
  for message; do
    echo -e "${message}" >&2
  done

  exit 1
}

function octopus::helm::repo() {
  helm repo add ${HELM_REPO_NAME} ${HELM_REPO_PATH}
  helm repo update
}

function octopus::helm::plugin() {
  if [[ -n "$(command -v helm push)" ]]; then
    return 0
  fi

  octopus::log::info "installing helm push"
  helm plugin install https://github.com/chartmuseum/helm-push.git
  helm push --help 2>&1
}

function octopus::charts::package() {
  # loop the charts directory
  for dir in */ ; do
      if git diff HEAD^ --unified=0 "$dir" | grep 'diff --git' 2>&1 ; then
          octopus::log::info "Directory $dir contain git changes, start helm package"
          helm package "$dir" -d /tmp/octopus-charts
      else
          octopus::log::info "Ignore directory $dir, it has not been modified."
      fi
  done
}

function octopus::charts::upload() {
  export HELM_REPO_USERNAME=${HELM_REPO_USERNAME}
  export HELM_REPO_PASSWORD=${HELM_REPO_PASSWORD}

  octopus::log::info "upload packaged helm charts"
  # loop the packaged helm charts
  for chart in /tmp/octopus-charts/*.tgz ; do
    echo "$chart"
    helm push "$chart" ${HELM_REPO_NAME}
  done
}

octopus::helm::start
