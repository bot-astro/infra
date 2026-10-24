# Astro infra

GitOps repo for Astro.
The IaC is in a personal repository: [gport](https://github.com/Giuliopime/gport)

#### ArgoCD
ArgoCD watches `apps/*/envs/*` and deploys each folder in the namespace named after the env (`astro`, `astro-staging`).
The cluster itself (Hetzner, ArgoCD, sealed-secrets, nginx, cert-manager) lives in `Giuliopime/gport`. See `PLAN.md` for the design.


#### secrets management
Secrets cannot be commited to git, for this reason I use [sealed secrets](https://github.com/bitnami-labs/sealed-secrets)

1) Install `kubeseal` and `yq` on your local machine:
    ```shell
    brew install kubeseal yq
    ``` 
2) Follow [installation instructions](https://github.com/bitnami-labs/sealed-secrets?tab=readme-ov-file#installation) for sealed-secrets
    ```shell
    kubectl apply -k ./sealed-secrets-installation
    ```
3) Prepare secrets:  
   In each folder under `/apps/*/envs/*` there can be a `/secrets` folder.  
   Each contains a `*-secret.template.yml` file, duplicate it and remove the `.template` part from the new file name. Then fill out the values.
4) Seal the secrets:
    ```shell
    chmod +x scripts/seal-secrets.sh && scripts/seal-secrets.sh
    ```
   (Recommended) You can also provide a specific folder to the script, instead of sealing all secrets: `scripts/seal-secrets.sh cert-manager`

5) Commit and push the changes