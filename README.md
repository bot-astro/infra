# Astro infra

GitOps repo for Astro.
The IaC is in a personal repository: [gport](https://github.com/Giuliopime/gport)

#### ArgoCD
ArgoCD watches `apps/*/envs/*` and deploys each folder in the namespace named after the env (`astro`, `astro-staging`).  
Semaphore updates the `version.yml` of each app when it deploys, you shouldn't need to touch that by hand.  
Staging is kept at 0 replicas to save money, to use it set `replicas: 1` (and `suspend: false` for the cronjob) in `apps/*/envs/astro-staging`, and put it back afterwards.
The cluster itself (Hetzner, ArgoCD, sealed-secrets, nginx, cert-manager) lives in `Giuliopime/gport`.

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

#### monitoring (Grafana dashboards and alerts)
Prometheus and Grafana come from kube-prometheus-stack, installed by [gport](https://github.com/Giuliopime/gport). The dashboards and the alerting rules live in `apps/grafana/envs/monitoring` and are loaded by the Grafana sidecars:
- `dashboards/*.json`: Overview, Bot (Discord), Voice (temporary VCs), Resources (Kubernetes + JVM). Each ends up in a ConfigMap labelled `grafana_dashboard`
- `alerting.yml`: contact point, notification policy and alert rules, in a ConfigMap labelled `grafana_alert`
- `infisical-secret.yml`: syncs `DISCORD_WEBHOOK_URL` from Infisical (project of the bot, `prod`, folder `/monitoring`) into the `grafana-alerting` Secret of the `monitoring` namespace

Needed once, in the gport values of kube-prometheus-stack:
```yaml
grafana:
  envFromSecrets:
    - name: grafana-alerting
      optional: true
  sidecar:
    alerts:
      enabled: true
      label: grafana_alert
      labelValue: "1"
      searchNamespace: ALL
```
Create the webhook in Discord (channel settings -> Integrations -> Webhooks) and save its URL as `DISCORD_WEBHOOK_URL` in Infisical, folder `/monitoring`.  
Dashboards are provisioned, so edit the JSON files instead of the UI (changes made in the UI are not saved).


## Technical notes

#### CPU requests and limits
Pods set a CPU **request** but deliberately **no CPU limit**.  
On startup every pod needs a lot of CPU for a short time (class loading, Spring context, shard login), then it drops to a very small usage. A limit would throttle that burst and make startups (and probe failures) much slower, while with only a request the idle CPU of the node is shared between pods.  
Memory is the opposite: request and limit are equal, since memory can't be shared or throttled.  
Side effect: without a limit, the JVM sees all the cores of the node (JDK 19+ ignores the request), so it would size GC, JIT and Netty threads and glibc malloc arenas for e.g. 16 cores. The services compensate with `-XX:ActiveProcessorCount` and `MALLOC_ARENA_MAX=2`, set in the Gradle config of the `astro` repo (`service-conventions.gradle.kts` and each service's `build.gradle.kts`). Don't add a CPU limit to fix this, change those flags.

#### Bot metrics and the pod label
The bot pods push their metrics to Prometheus over OTLP and Prometheus doesn't add a pod label (the pod name arrives only in `target_info` as `job_id`). A series is identified by its name and labels, so without a label of their own all the pods write into the same series: counters jump between the values of the pods, and `rate()` / `increase()` read every drop as a counter reset and return inflated numbers (`resets(http_discord_requests_total[1h])` is in the hundreds).  
The bot adds the `pod_id` tag only where it is needed: the shard gauges and the counters and timers (`astro.vc.created`, `astro.vc.create.duration`, `astro.interactions`, `astro.interactions.duration`). JVM and Spring metrics have no pod label, so the JVM panels of the Resources dashboard still mix all the pods.  
In queries on counters and timers always aggregate (`sum(rate(...))`, `histogram_quantile(0.95, sum by (le) (rate(...)))`), otherwise you get one line per pod. A new counter or timer in the bot must have the `pod_id` tag.
