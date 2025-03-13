# Scripts

## Deploy AKS cluster

Run the script `deploy-aks.sh` to deploy AKS cluster for VN2. Requires elevated permissions on our subscription to run this and set up the cluster

## Deploy VN2 Helm

Run `deploy-vn2-helm.sh` to deploy VN2 Helm chart.

## Deploy a yaml deployment

Run `./create_vn2_deployment_checked.py` with the yaml file as an argument. YAML must contain only one resource with `kind: Deployment`, and it must have valid pod labels and selector. The script will check if deployment is succeed, then check for a further 5 minute that the deployment is stable, no restarts etc.

## Tear down yaml deployment

Run `./cleanup_vn2_deployment_checked.py` with the yaml file as an argument. Will wait for all pods to be deleted.

## Clean up VN2 Helm

Run `clean-vn2-helm.sh` to clean up VN2 Helm chart. All pods must be deleted first.

## Delete AKS cluster

Run the script `delete-aks.sh` to delete the cluster
