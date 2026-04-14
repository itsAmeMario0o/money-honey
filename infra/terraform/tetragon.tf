// Tetragon runs as a DaemonSet on every node, enforcing TracingPolicies
// at the kernel via eBPF. Installed via Helm — the only Helm release in
// this cluster per CLAUDE.md line 217.
//
// Values match CLAUDE.md lines 298-318 exactly. helm provider 2.17 uses
// the block form for `set {}`; VSCode's language server may show this
// as "unexpected block" if it has loaded a helm 3.x schema. Trust
// `terraform validate` over the editor.

resource "helm_release" "tetragon" {
  name       = "tetragon"
  repository = "https://helm.cilium.io"
  chart      = "tetragon"
  namespace  = "kube-system"
  version    = var.tetragon_chart_version

  // Process credential + namespace tracking for Splunk audit.
  set {
    name  = "tetragon.enableProcessCred"
    value = "true"
  }
  set {
    name  = "tetragon.enableProcessNs"
    value = "true"
  }

  // JSON event log — Fluent Bit tails this file and ships to Splunk HEC.
  // exportFilename is a filename ONLY (not a full path) — the chart
  // concatenates it onto its internal exportDirectory. Passing a full
  // path here doubles the directory prefix. Keeping just "tetragon.log"
  // gives us a clean /var/run/cilium/tetragon/tetragon.log on the host.
  set {
    name  = "tetragon.exportFilename"
    value = "tetragon.log"
  }

  // Prometheus metrics on port 2112, scraped by OTel Collector in step 4.
  set {
    name  = "tetragon.prometheus.enabled"
    value = "true"
  }
  set {
    name  = "tetragon.prometheus.port"
    value = "2112"
  }
  set {
    name  = "tetragon.prometheus.serviceMonitor.enabled"
    value = "false"
  }

  // Runtime hooks — needed for policy enforcement at pod start.
  set {
    name  = "rthooks.enabled"
    value = "true"
  }
  set {
    name  = "rthooks.interface"
    value = "oci-hooks"
  }

  // Resource requests / limits — right-sized for B2als_v2 nodes.
  set {
    name  = "tetragon.resources.requests.cpu"
    value = "100m"
  }
  set {
    name  = "tetragon.resources.requests.memory"
    value = "128Mi"
  }
  set {
    name  = "tetragon.resources.limits.cpu"
    value = "500m"
  }
  set {
    name  = "tetragon.resources.limits.memory"
    value = "512Mi"
  }

  depends_on = [azurerm_kubernetes_cluster.money_honey]
}
