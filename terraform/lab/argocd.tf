locals {
  argocd_manifest_dir = "${path.module}/argocd/manifests"
  argocd_docs = [
    for doc in split("\n---\n", trimspace(file("${local.argocd_manifest_dir}/install.yaml"))) :
    yamldecode(doc)
  ]
  argocd_docs_nonnull = [for manifest in local.argocd_docs : manifest if manifest != null]
  argocd_namespace = yamldecode(<<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: argocd
    YAML
  )
  argocd_namespaced_kinds = toset([
    "ConfigMap",
    "Secret",
    "Service",
    "ServiceAccount",
    "Role",
    "RoleBinding",
    "Deployment",
    "StatefulSet",
    "DaemonSet",
    "ReplicaSet",
    "NetworkPolicy",
    "PodDisruptionBudget",
    "Ingress",
  ])

  # Keep critical Argo pods out of BestEffort QoS so startup churn does not OOM-kill them.
  argocd_container_resources = {
    "argocd-application-controller" = {
      container_name = "argocd-application-controller"
      resources = {
        requests = {
          cpu    = "200m"
          memory = "512Mi"
        }
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
      }
    }
    "argocd-repo-server" = {
      container_name = "argocd-repo-server"
      resources = {
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
      }
    }
    "argocd-server" = {
      container_name = "argocd-server"
      resources = {
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
      }
    }
    "argocd-dex-server" = {
      container_name = "dex"
      resources = {
        requests = {
          cpu    = "50m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "250m"
          memory = "256Mi"
        }
      }
    }
    "argocd-notifications-controller" = {
      container_name = "argocd-notifications-controller"
      resources = {
        requests = {
          cpu    = "50m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "250m"
          memory = "256Mi"
        }
      }
    }
    "argocd-applicationset-controller" = {
      container_name = "argocd-applicationset-controller"
      resources = {
        requests = {
          cpu    = "50m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "250m"
          memory = "256Mi"
        }
      }
    }
  }

  argocd_namespaced_manifests = [
    for manifest in local.argocd_docs_nonnull :
    jsondecode(jsonencode(
      merge(
        manifest,
        {
          metadata = merge(
            lookup(manifest, "metadata", {}),
            contains(local.argocd_namespaced_kinds, manifest.kind) && try(manifest.metadata.namespace, null) == null
            ? { namespace = "argocd" }
            : {}
          )
        }
      )
    ))
  ]

  argocd_other_manifests = [
    for manifest in local.argocd_namespaced_manifests :
    jsondecode(
      (
        contains(["Deployment", "StatefulSet"], manifest.kind) &&
        lookup(lookup(manifest, "metadata", {}), "namespace", "") == "argocd" &&
        contains(keys(local.argocd_container_resources), lookup(lookup(manifest, "metadata", {}), "name", ""))
        ) ? jsonencode(
        merge(
          manifest,
          {
            spec = merge(
              try(manifest.spec, {}),
              {
                template = merge(
                  try(manifest.spec.template, {}),
                  {
                    spec = merge(
                      try(manifest.spec.template.spec, {}),
                      {
                        containers = [
                          for container in try(manifest.spec.template.spec.containers, []) :
                          jsondecode(
                            container.name == local.argocd_container_resources[manifest.metadata.name].container_name
                            ? jsonencode(merge(container, { resources = local.argocd_container_resources[manifest.metadata.name].resources }))
                            : jsonencode(container)
                          )
                        ]
                      }
                    )
                  }
                )
              }
            )
          }
        )
      ) : jsonencode(manifest)
    )
  ]

  argocd_webhook_kinds = toset([
    "MutatingWebhookConfiguration",
    "ValidatingWebhookConfiguration",
  ])
  argocd_repo_has_ssh = length(trimspace(var.ARGOCD_REPO_SSH_PRIVATE_KEY)) > 0
  argocd_repo_has_basic = (
    length(trimspace(var.ARGOCD_REPO_USERNAME)) > 0 &&
    length(trimspace(var.ARGOCD_REPO_PASSWORD)) > 0
  )
  argocd_repo_has_creds = local.argocd_repo_has_ssh || local.argocd_repo_has_basic
}

resource "kubernetes_manifest" "argocd_namespace" {
  manifest   = local.argocd_namespace
  depends_on = [module.cluster1]
}

resource "kubernetes_manifest" "argocd" {
  for_each = {
    for manifest in local.argocd_other_manifests :
    format(
      "%s/%s/%s",
      manifest.kind,
      lookup(manifest.metadata, "namespace", "_cluster"),
      manifest.metadata.name
    ) => manifest
  }
  manifest        = each.value
  computed_fields = contains(local.argocd_webhook_kinds, each.value.kind) ? ["metadata.creationTimestamp"] : null
  depends_on      = [kubernetes_manifest.argocd_namespace]
}

resource "kubernetes_manifest" "argocd_repo_secret" {
  count = local.argocd_repo_has_creds ? 1 : 0
  manifest = {
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "repo-lab"
      namespace = "argocd"
      labels = {
        "argocd.argoproj.io/secret-type" = "repository"
      }
    }
    stringData = merge(
      {
        url  = var.ARGOCD_REPO_URL
        type = "git"
      },
      local.argocd_repo_has_ssh ? { sshPrivateKey = var.ARGOCD_REPO_SSH_PRIVATE_KEY } : {},
      local.argocd_repo_has_basic ? {
        username = var.ARGOCD_REPO_USERNAME
        password = var.ARGOCD_REPO_PASSWORD
      } : {}
    )
  }
  depends_on = [kubernetes_manifest.argocd]
}

resource "kubernetes_manifest" "argocd_app" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "talos-gitops"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.ARGOCD_REPO_URL
        targetRevision = var.ARGOCD_REPO_REVISION
        path           = var.ARGOCD_REPO_PATH
        directory = {
          recurse = true
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "default"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true",
        ]
      }
    }
  }
  depends_on = [
    kubernetes_manifest.argocd,
    kubernetes_manifest.argocd_repo_secret,
  ]
}
