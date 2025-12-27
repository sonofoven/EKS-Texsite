#!/bin/sh

Flow:
bootstrap:
    
    # Infra phase
    terraform apply:
            create ecr repo (this time w/ a lifecycle)
            create policies
            create role
            create eks w/ role
            add prometheus + graphana integration w/ graphana exposed
    grab output, save as gh variable

    # Seed initial image
    compile latex -> html
    create dockerfile
    push dockerfile up to ecr

    # Append a
    Copy config creds to local machine to access via kubectl
    install fluxCD
    
    apply manifests w/ flux automatically reading repo for updates


CI: ON LATEX FILE CHANGE ONLY
    compile latex -> html
    create dockerfile
    push dockerfile up to ecr

    # No need for a CI on manifests cuz thats what flux is for

gitops:
    updates git to latest image from ecr to push into the cluster
