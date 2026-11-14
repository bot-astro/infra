# Astro infra

GitOps repo for Astro.
The IaC is in a personal repository: [gport](https://github.com/Giuliopime/gport)

#### ArgoCD
ArgoCD watches `apps/*/envs/*` and deploys each folder in the namespace named after the env (`astro`, `astro-staging`).  
Semaphore updates the `version.yml` of each app when it deploys, you shouldn't need to touch that by hand.  
Staging is kept at 0 replicas to save money, to use it set `replicas: 1` (and `suspend: false` for the cronjob) in `apps/*/envs/astro-staging`, and put it back afterwards.
The cluster itself (Hetzner, ArgoCD, sealed-secrets, nginx, cert-manager) lives in `Giuliopime/gport`.


#### CPU requests and limits
Pods set a CPU **request** but deliberately **no CPU limit**.  
On startup every pod needs a lot of CPU for a short time (class loading, Spring context, shard login), then it drops to a very small usage. A limit would throttle that burst and make startups (and probe failures) much slower, while with only a request the idle CPU of the node is shared between pods.  
Memory is the opposite: request and limit are equal, since memory can't be shared or throttled.  
Side effect: without a limit, the JVM sees all the cores of the node (JDK 19+ ignores the request), so it would size GC, JIT and Netty threads and glibc malloc arenas for e.g. 16 cores. The services compensate with `-XX:ActiveProcessorCount` and `MALLOC_ARENA_MAX=2`, set in the Gradle config of the `astro` repo (`service-conventions.gradle.kts` and each service's `build.gradle.kts`). Don't add a CPU limit to fix this, change those flags.

#### secrets management
Configs and secrets of the apps are in [Infisical](https://infisical.com), the Infisical operator syncs them in the cluster (see the `infisical-secret.yml` files).  
The few secrets needed to bootstrap cannot be commited to git, for this reason I use [sealed secrets](https://github.com/bitnami-labs/sealed-secrets)

1) Install `kubeseal` and `yq` on your local machine:
    ```shell
    brew install kubeseal yq
    ``` 
2) sealed-secrets is installed on the cluster by [gport](https://github.com/Giuliopime/gport)
3) Prepare secrets:  
   In each folder under `/apps/*/envs/*` there can be a `/secrets` folder.  
   Each contains a `*-secret.template.yml` file, duplicate it and remove the `.template` part from the new file name. Then fill out the values.
4) Seal the secrets:
    ```shell
    chmod +x scripts/seal-secrets.sh && scripts/seal-secrets.sh
    ```
   (Recommended) You can also provide a specific folder to the script, instead of sealing all secrets: `scripts/seal-secrets.sh cert-manager`

5) Commit and push the changes

#### terraform
Cloudflare (R2, CDN, DNS) and BigQuery are managed in the [terraform](terraform) folder, see the README in there.
