resource "kubernetes_namespace_v1" "ray_system" {
  metadata {
    name = "ray-system"
  }

  depends_on = [module.data_addons]
}

resource "kubernetes_manifest" "ray_cluster" {
  depends_on = [
    kubernetes_namespace_v1.ray_system
  ]

  manifest = {
    apiVersion = "ray.io/v1"
    kind = "RayCluster"
    metadata = {
      name = "ray-cluster"
      namespace = kubernetes_namespace_v1.ray_system.metadata[0].name
    }
    spec = {
      rayVersion = "2.9.0"
      headGroupSpec = {
        rayStartParams = {
          "dashboard-host" = "0.0.0.0",
          block = "true",
          "metrics-export-port" = "8080",
          "enable-usage-stats" = "false"
        }
        template = {
          spec = {
            containers = [
              {
                name = "ray-head"
                image = "rayproject/ray:2.9.0"
                ports = [
                  {
                    containerPort = 6379
                    name = "gcs-server"
                  },
                  {
                    containerPort = 8265
                    name = "dashboard"
                  },
                  {
                    containerPort = 10001
                    name = "client"
                  },
                  {
                    containerPort = 8080
                    name = "metrics"
                  }
                ]
                resources = {
                  limits = {
                    cpu = "2"
                    memory = "4Gi"
                  }
                  requests = {
                    cpu = "2"
                    memory = "4Gi"
                  }
                }
              }
            ]
          }
        }
      }
      workerGroupSpecs = [
        {
          groupName = "worker-group"
          replicas = 1
          minReplicas = 1
          maxReplicas = 5
          rayStartParams = {
            "metrics-export-port" = "8080",
            "enable-usage-stats" = "false"
          }
          template = {
            spec = {
              containers = [
                {
                  name = "ray-worker"
                  image = "rayproject/ray:2.9.0"
                  ports = [
                    {
                      containerPort = 8080
                      name = "metrics"
                    }
                  ]
                  lifecycle = {
                    preStop = {
                      exec = {
                        command = ["/bin/sh", "-c", "ray stop"]
                      }
                    }
                  }
                  resources = {
                    limits = {
                      cpu = "2"
                      memory = "4Gi"
                      "nvidia.com/gpu" = 1
                    }
                    requests = {
                      cpu = "2"
                      memory = "4Gi"
                      "nvidia.com/gpu" = 1
                    }
                  }
                }
              ]
              nodeSelector = {
                NodeGroupType = "g5-gpu-karpenter"
              }
              tolerations = [
                {
                  key = "nvidia.com/gpu"
                  operator = "Exists"
                  effect = "NoSchedule"
                }
              ]
            }
          }
        }
      ]
    }
  }

  field_manager {
    force_conflicts = true
  }
}

resource "kubernetes_manifest" "ray_dashboard_ingress" {
  depends_on = [kubernetes_manifest.ray_cluster]

  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind = "Ingress"
    metadata = {
      name = "ray-dashboard"
      namespace = kubernetes_namespace_v1.ray_system.metadata[0].name
      annotations = {
        "nginx.ingress.kubernetes.io/proxy-read-timeout" = "3600"
        "nginx.ingress.kubernetes.io/proxy-send-timeout" = "3600"
        "nginx.ingress.kubernetes.io/proxy-connect-timeout" = "3600"
      }
    }
    spec = {
      ingressClassName = "nginx"
      rules = [
        {
          host = "ray.domainsandbox.net"
          http = {
            paths = [
              {
                path = "/"
                pathType = "Prefix"
                backend = {
                  service = {
                    name = "ray-cluster-head-svc"
                    port = {
                      number = 8265
                    }
                  }
                }
              }
            ]
          }
        }
      ]
    }
  }
}
