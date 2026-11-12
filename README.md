# Astro infra

GitOps repo for Astro.  
The cluster itself (Hetzner, ArgoCD, sealed-secrets, nginx, cert-manager, Infisical operator) is in a personal repository: [gport](https://github.com/Giuliopime/gport)

#### ArgoCD
`root-argocd-app.yml` creates the appset in `appsets/`, which watches `apps/*/envs/*` and deploys each folder in the namespace named after the env (`astro` for production, `astro-staging`).  
Each app has a `base` and an `envs/<env>` folder with the patches for that env (version, replicas, resources, ingress).  
Semaphore bumps `version.yml` through `scripts/deploy.sh` on every deploy, you shouldn't need to touch it by hand.

> [!NOTE]
> Staging runs at 0 replicas to save money (the cronjob is suspended too). To use it set `replicas: 1` (and `suspend: false`) in `apps/*/envs/astro-staging`, push, and scale it down again afterwards.

#### Secrets
Everything that changes lives in [Infisical](https://app.infisical.com) (`prod` and `staging` environments), the Infisical operator turns it into the Kubernetes secrets the apps use (`apps/*/envs/*/infisical-secret.yml`).  
The only secrets in git are the few needed to bootstrap, encrypted with [sealed secrets](https://github.com/bitnami-labs/sealed-secrets) (the Infisical identity id and the image registry credentials).

To change them:
1) `brew install kubeseal yq`
2) In each folder under `/apps/*/envs/*` there can be a `/secrets` folder.  
   Each contains a `*-secret.template.yml` file, duplicate it and remove the `.template` part from the new file name. Then fill out the values (these files are gitignored).
3) Seal them, you can pass an app folder to seal only that one:
    ```shell
    scripts/seal-secrets.sh infisical
    ```
4) Commit and push the `*-sealed.yml` files

#### Terraform
Cloudflare (R2, CDN, DNS) and BigQuery are managed in [terraform](terraform), see its README.
