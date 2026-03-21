#!/usr/bin/env bash
# openspp.sh -- OpenSPP Social Protection Platform deployer
#
# OpenSPP is an Odoo 17-based platform. It requires PostgreSQL (not MySQL).
# PostgreSQL is deployed as inline Kubernetes manifests inside the openspp
# Helm chart (templates/postgresql.yaml) using docker.io/postgres:16.
# No helm dep update / OCI registry pull is required for the chart itself.
#
# Shared infra reused from the existing stack: NGINX ingress.
# Redis and Kafka are available within the cluster if OpenSPP modules need them.

OPENSPP_CHART_DIR="${OPENSPP_CHART_DIR:-$RUN_DIR/src/deployer/helm/openspp}"

#------------------------------------------------------------
# Description : Deploys OpenSPP via its local Helm chart.
#               PostgreSQL is deployed as inline manifests (no subchart).
# Usage       : deployOpenSPP
#------------------------------------------------------------
function deployOpenSPP() {
  log_section "Deploying OpenSPP"

  log_step "Creating namespace $OPENSPP_NAMESPACE"
  createNamespace "$OPENSPP_NAMESPACE"
  check_command_execution $? "createNamespace $OPENSPP_NAMESPACE"
  log_ok

  log_step "Updating FQDNs"
  update_fqdn "$OPENSPP_CHART_DIR/values.yaml" "mifos.gazelle.test" "$GAZELLE_DOMAIN"
  update_fqdn "$OPENSPP_CHART_DIR/values.yaml" "mifos.gazelle.localhost" "$GAZELLE_DOMAIN"
  log_ok

  # No subchart dependencies — PostgreSQL is inline in templates/postgresql.yaml.
  # ensure_helm_dependencies intentionally skipped: nothing to download.

  log_step "Helm chart (openspp)"
  local helm_cmd="helm upgrade --install --wait --timeout 600s $OPENSPP_RELEASE_NAME $OPENSPP_CHART_DIR -n $OPENSPP_NAMESPACE"
  local helm_output
  helm_output=$(run_as_user "$helm_cmd" 2>&1)
  local helm_rc=$?
  if [ $helm_rc -ne 0 ]; then
    log_error "helm upgrade --install openspp failed with:"
    echo "$helm_output" >&2
  fi
  check_command_execution $helm_rc "helm upgrade --install openspp"
  log_ok

  log_banner "OpenSPP Deployed"
}
