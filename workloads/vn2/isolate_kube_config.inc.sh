# This snippet makes it possible to run multiple AKS-related scripts in parallel

curr_kube_config="${KUBECONFIG:-$HOME/.kube/config}"
new_kube_config="$(mktemp -t kubeconfig.XXXXXX)"
export KUBECONFIG="$new_kube_config"
cp "$curr_kube_config" "$new_kube_config"
