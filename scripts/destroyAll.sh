#!/bin/sh

flux uninstall
kubectl delete ingress --all -A
kubectl delete svc -A --field-selector spec.type=LoadBalancer
cd ../terraform/
terraform destroy --auto-approve
