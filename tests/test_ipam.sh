#!/bin/bash

CURR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
[ -d "$CURR_DIR" ] || { echo "FATAL: no current dir (maybe running in zsh?)";  exit 1; }

# shellcheck source=./common.sh
source "$CURR_DIR/common.sh"

export CURRENT_STAGE="Test | IPAM"

highlight "[START] IPAM $EXTRA_TITLE"

clustername="ipamtest"
subnet="172.45.0.0/16"
expectedIPGateway="172.45.0.1" # k3d defaults to subnet_start+1 for the Gateway IP
expectedIPLabelServer0="172.45.0.3"
expectedIPServer0="$expectedIPLabelServer0/16" # k3d excludes the subnet_start (x.x.x.0) and then uses IPs in sequential order, but .2 will be used by the tools container that gathers information at start
expectedIPServerLB="172.45.0.4/16"

info "Creating cluster $clustername..."
$EXE cluster create $clustername --timeout 360s --subnet $subnet || failed "could not create cluster $clustername"

function check_cluster() {
  info "Checking we have access to the cluster..."
  check_clusters "$clustername" || failed "error checking cluster"

  info "Checking IP Subnet/IP values..."
  if [[ $(docker network inspect k3d-$clustername | jq '.[0].IPAM.Config[0].Subnet') != "\"$subnet\"" ]]; then
    failed "Subnet does not match expected value: $(docker network inspect k3d-$clustername | jq '.[0].IPAM.Config[0].Subnet') != \"$subnet\""
  fi
  if [[ $(docker network inspect k3d-$clustername | jq '.[0].IPAM.Config[0].Gateway') != "\"$expectedIPGateway\"" ]]; then
    failed "Gateway IP does not match expected value"
  fi
  if [[ $(docker network inspect k3d-$clustername | jq ".[0].Containers | .[] | select(.Name == \"k3d-$clustername-server-0\") | .IPv4Address") != "\"$expectedIPServer0\"" ]]; then
    failed "Container k3d-$clustername-server-0's IP does not match expected value"
  fi

  info "Checking Labels..."
  docker_assert_container_label "k3d-$clustername-server-0" "k3d.cluster.network.iprange=$subnet" || failed "missing label 'k3d.cluster.network.iprange=$subnet' on k3d-$clustername-server-0"
  docker_assert_container_label "k3d-$clustername-server-0" "k3d.node.staticIP=$expectedIPLabelServer0" || failed "missing label 'k3d.node.staticIP=$expectedIPLabelServer0' on k3d-$clustername-server-0"
}

check_cluster

info "Stopping & Starting cluster $clustername..."
$EXE cluster stop $clustername || failed "error stopping cluster $clustername"
sleep 3
$EXE cluster start $clustername || failed "error starting cluster $clustername"

check_cluster

info "Deleting cluster $clustername..."
$EXE cluster delete $clustername || failed "could not delete the cluster $clustername"

exit 0


