#!/bin/bash

export INSTALL_PROM=yes

# Create the cluster
if ! kind create cluster --config cluster.yaml; then
    exit 1
fi;

# Untaint the master
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

# Applies the manifests
kubectl --context kind-kind apply -f bundle/00-traefik-crds.yaml
kubectl --context kind-kind apply -f bundle

# Install metrics server
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update
helm upgrade --install --set args={--kubelet-insecure-tls} metrics-server metrics-server/metrics-server --namespace kube-system

# Install stuff via Helm
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
    --namespace kubernetes-dashboard \
    --set protocolHttp=true \
    --set serviceAccount.create=false \
    --set serviceAccount.name=admin-user \
    --set metricsScraper.enabled=true
if [ "${INSTALL_PROM}" = "yes" ]; then
    helm install prometheus -n monitoring prometheus-community/kube-prometheus-stack
fi;

kubectl apply -f vault

sleep 5
echo ""
echo "Traefik: http://traefik.localhost"
echo "Dashboard: http://dashboard.localhost"
if [ "${INSTALL_PROM}" = "yes" ]; then
    echo "http://grafana.localhost credentials: $(kubectl get secret -n monitoring prometheus-grafana -oyaml | grep admin-user| cut -d: -f2|tr -d \  | base64 -d):$(kubectl get secret -n monitoring prometheus-grafana -oyaml | grep admin-password| cut -d: -f2|tr -d \  | base64 -d)\
    "
fi

echo "The vault unlock secret (root token) lives in the vault/vault-unlock secret, to get the root token wait up to one minute then run"
echo "  kubectl get secret -n vault vault-unlock -ojson | jq -r .data.value | base64 -d | jq -r .root_token"
