// Tetragon runs as a DaemonSet on every node, enforcing TracingPolicies
// at the kernel via eBPF. Installed via Helm — the only Helm release in
// this cluster per CLAUDE.md line 217.
//
// Values match CLAUDE.md lines 298-318 exactly. Using the `set = [...]`
// attribute form so the file stays clean in both helm provider 2.12+
// and 3.x.

resource "helm_release" "tetragon" {
  name       = "tetragon"
  repository = "https://helm.cilium.io"
  chart      = "tetragon"
  namespace  = "kube-system"
  version    = var.tetragon_chart_version

  set = [
    // Process credential + namespace tracking are needed for Splunk audit.
    { name = "tetragon.enableProcessCred", value = "true" },
    { name = "tetragon.enableProcessNs", value = "true" },

    // JSON event log — Fluent Bit tails this file and ships to Splunk HEC.
    { name = "tetragon.exportFilename", value = "/var/run/cilium/tetragon/tetragon.log" },

    // Prometheus metrics on port 2112, scraped by OTel Collector in step 4.
    { name = "tetragon.prometheus.enabled", value = "true" },
    { name = "tetragon.prometheus.port", value = "2112" },
    { name = "tetragon.prometheus.serviceMonitor.enabled", value = "false" },

    // Runtime hooks — needed for policy enforcement at pod start.
    { name = "rthooks.enabled", value = "true" },
    { name = "rthooks.interface", value = "oci-hooks" },

    // Resource requests / limits — right-sized for B2als_v2 nodes.
    { name = "tetragon.resources.requests.cpu", value = "100m" },
    { name = "tetragon.resources.requests.memory", value = "128Mi" },
    { name = "tetragon.resources.limits.cpu", value = "500m" },
    { name = "tetragon.resources.limits.memory", value = "512Mi" },
  ]

  depends_on = [azurerm_kubernetes_cluster.money_honey]
}
