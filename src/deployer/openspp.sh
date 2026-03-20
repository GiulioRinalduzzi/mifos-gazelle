#!/usr/bin/env bash
# openspp.sh -- OpenSPP Social Protection Platform deployer
#
# OpenSPP is an Odoo 17-based platform. It requires PostgreSQL (not MySQL),
# which is deployed as a subchart within the openspp Helm chart and does not
# share the MySQL instance used by Fineract/MifosX.
#
# Shared infra reused from the existing stack: NGINX ingress.
# Redis and Kafka are available within the cluster if OpenSPP modules need them.

OPENSPP_CHART_DIR="${OPENSPP_CHART_DIR:-$RUN_DIR/src/deployer/helm/openspp}"

#------------------------------------------------------------
# Description : Deploys OpenSPP via its local Helm chart.
#               PostgreSQL is included as a subchart.
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

  ensure_helm_dependencies "$OPENSPP_CHART_DIR"

  log_step "Helm chart (openspp)"
  local helm_cmd="helm upgrade --install --wait --timeout 600s $OPENSPP_RELEASE_NAME $OPENSPP_CHART_DIR -n $OPENSPP_NAMESPACE"
  if [ "$debug" = true ]; then
    run_as_user "$helm_cmd"
  else
    run_as_user "$helm_cmd" >> /dev/null 2>&1
  fi
  check_command_execution $? "helm upgrade --install openspp"
  log_ok

  log_banner "OpenSPP Deployed"
}
