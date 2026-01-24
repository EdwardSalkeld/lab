locals {
  kubeconfig = yamldecode(module.cluster1.kubeconfig)
  traefik_manifests = [
    yamldecode(<<-YAML
      apiVersion: v1
      kind: Namespace
      metadata:
        name: traefik
      YAML
    ),
    yamldecode(<<-YAML
      apiVersion: v1
      kind: ServiceAccount
      metadata:
        name: traefik
        namespace: traefik
      YAML
    ),
    yamldecode(<<-YAML
      apiVersion: rbac.authorization.k8s.io/v1
      kind: ClusterRole
      metadata:
        name: traefik
      rules:
        - apiGroups: [""]
          resources: ["services", "endpoints", "secrets", "nodes"]
          verbs: ["get", "list", "watch"]
        - apiGroups: ["extensions", "networking.k8s.io"]
          resources: ["ingresses", "ingressclasses"]
          verbs: ["get", "list", "watch"]
      YAML
    ),
    yamldecode(<<-YAML
      apiVersion: rbac.authorization.k8s.io/v1
      kind: ClusterRoleBinding
      metadata:
        name: traefik
      roleRef:
        apiGroup: rbac.authorization.k8s.io
        kind: ClusterRole
        name: traefik
      subjects:
        - kind: ServiceAccount
          name: traefik
          namespace: traefik
      YAML
    ),
    yamldecode(<<-YAML
      apiVersion: networking.k8s.io/v1
      kind: IngressClass
      metadata:
        name: traefik
      spec:
        controller: traefik.io/ingress-controller
      YAML
    ),
    yamldecode(<<-YAML
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: traefik
        namespace: traefik
      spec:
        replicas: 1
        selector:
          matchLabels:
            app: traefik
        template:
          metadata:
            labels:
              app: traefik
          spec:
            serviceAccountName: traefik
            containers:
              - name: traefik
                image: traefik:v2.11
                args:
                  - --entrypoints.web.address=:80
                  - --entrypoints.websecure.address=:443
                  - --providers.kubernetesingress
                  - --providers.kubernetesingress.ingressclass=traefik
                  - --api.insecure=true
                ports:
                  - name: web
                    containerPort: 80
                  - name: websecure
                    containerPort: 443
                  - name: admin
                    containerPort: 8080
      YAML
    ),
    yamldecode(<<-YAML
      apiVersion: v1
      kind: Service
      metadata:
        name: traefik
        namespace: traefik
      spec:
        type: LoadBalancer
        loadBalancerIP: 10.4.1.88
        allocateLoadBalancerNodePorts: true
        selector:
          app: traefik
        ports:
          - name: web
            port: 80
            targetPort: web
          - name: websecure
            port: 443
            targetPort: websecure
          - name: admin
            port: 8080
            targetPort: admin
    YAML
  ),
    yamldecode(<<-YAML
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: whoami
        namespace: default
      spec:
        replicas: 1
        selector:
          matchLabels:
            app: whoami
        template:
          metadata:
            labels:
              app: whoami
          spec:
            containers:
              - name: whoami
                image: traefik/whoami:v1.10
                ports:
                  - containerPort: 80
      YAML
    ),
    yamldecode(<<-YAML
      apiVersion: v1
      kind: Service
      metadata:
        name: whoami
        namespace: default
      spec:
        selector:
          app: whoami
        ports:
          - port: 80
            targetPort: 80
      YAML
    ),
    yamldecode(<<-YAML
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata:
        name: whoami
        namespace: default
      spec:
        ingressClassName: traefik
        rules:
          - host: whoami.k8s.alcachofa.faith
            http:
              paths:
                - path: /
                  pathType: Prefix
                  backend:
                    service:
                      name: whoami
                      port:
                        number: 80
    YAML
    ),
    yamldecode(<<-YAML
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata:
        name: traefik-dashboard
        namespace: traefik
      spec:
        ingressClassName: traefik
        rules:
          - host: dashboard.k8s.alcachofa.faith
            http:
              paths:
                - path: /
                  pathType: Prefix
                  backend:
                    service:
                      name: traefik
                      port:
                        number: 8080
    YAML
    ),
  ]
}

resource "kubernetes_manifest" "traefik" {
  for_each = { for idx, manifest in local.traefik_manifests : tostring(idx) => manifest }
  manifest = each.value
  depends_on = [module.cluster1]
}
