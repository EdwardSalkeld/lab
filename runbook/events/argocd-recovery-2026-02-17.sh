#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG=.kubeconfig kubectl -n argocd rollout restart deploy/argocd-repo-server deploy/argocd-server deploy/argocd-dex-server deploy/argocd-notifications-controller deploy/argocd-applicationset-controller
KUBECONFIG=.kubeconfig kubectl -n argocd delete pod argocd-application-controller-0
sleep 30
KUBECONFIG=.kubeconfig kubectl -n argocd get pods -o wide
