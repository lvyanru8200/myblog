---
title: "Kafka Op01"
subtitle: ""
date: 2022-07-26T11:15:19+08:00
lastmod: 2022-07-26T11:15:19+08:00
draft: true
author: "整挺好"
authorLink: ""
description: ""
license: "整挺好许可"
images: []

tags: ["kafka","operator","k8s"]
categories: ["operator"]

featuredImage: ""
featuredImagePreview: ""

hiddenFromHomePage: false
hiddenFromSearch: false
twemoji: false
lightgallery: true
ruby: true
fraction: true
fontawesome: true
linkToMarkdown: true
rssFullText: false

toc:
  enable: true
  auto: true
code:
  copy: true
  maxShownLines: 50
math:
  enable: false
  # ...
mapbox:
  # ...
share:
  enable: true
  # ...
comment:
  enable: true
  # ...
library:
  css:
    # someCSS = "some.css"
    # located in "assets/"
    # Or
    # someCSS = "https://cdn.example.com/some.css"
  js:
    # someJS = "some.js"
    # located in "assets/"
    # Or
    # someJS = "https://cdn.example.com/some.js"
seo:
  images: []
  # ...
---

<!--more-->

#### Kafka Operator代码阅读--kafka CRD逻辑

#### 本文主旨：

- [strimize-kafka-opertaor](https://github.com/strimzi/strimzi-kafka-operator) kafka CRD代码阅读

##### no bb 直接开始，以下用kafka Operator代替strimize-kafka-operator

#### Kafka Operator项目介绍

​		Kafka Operator是一个CNCF sandbox project，以Operator的形式将kafka上云并提供自运维能力，在目前已经具有的kafka operator中应该是最牛逼的一个，正好我的工作也与这个相关，所以读下kafka operator 0.30.x版本的源码，学习下他们的处理逻辑，但是本人不是搞java的，这个项目是java编写的，读懂大体的逻辑就行，看看他的一个处理过程。

<div align=center>
<img src="/images/4.png" />
</div>

从Kafka CRD的处理逻辑主要是在cluster-operator目录下,我们从他的main函数看起

<div align=center>
<img src="/images/5.png" />
</div>

```java
public static void main(String[] args) {
    LOGGER.info("ClusterOperator {} is starting", Main.class.getPackage().getImplementationVersion());
    // cluster operator启动，先根据环境变量实例化一个config配置，ClusterOperatorConfig后面看看
  	ClusterOperatorConfig config = ClusterOperatorConfig.fromMap(System.getenv());
    LOGGER.info("Cluster Operator configuration is {}", config);

    // java dns缓存配置，这里是设置成功解析的域名在jvm中缓存的时间
    Security.setProperty("networkaddress.cache.ttl", String.valueOf(config.getDnsCacheTtlSec()));

    // metrics服务配置
    VertxOptions options = new VertxOptions().setMetricsOptions(
        new MicrometerMetricsOptions()
            .setPrometheusOptions(new VertxPrometheusOptions().setEnabled(true))
            .setJvmMetricsEnabled(true)
            .setEnabled(true));
    Vertx vertx = Vertx.vertx(options);
    // 优雅关闭监控服务
    Runtime.getRuntime().addShutdownHook(new Thread(new ShutdownHook(vertx)));
    // k8s客户端
    KubernetesClient client = new DefaultKubernetesClient();
		// maybeCreateClusterRole方法如果执行成功，则执行PlatformFeaturesAvailability.create方法，如果			  PlatformFeaturesAvailability.create方法执行成功，则run()
    maybeCreateClusterRoles(vertx, config, client).onComplete(crs -> {
        if (crs.succeeded())    {
            PlatformFeaturesAvailability.create(vertx, client).onComplete(pfa -> {
                if (pfa.succeeded()) {
                    LOGGER.info("Environment facts gathered: {}", pfa.result());

                    run(vertx, client, pfa.result(), config).onComplete(ar -> {
                        if (ar.failed()) {
                            LOGGER.error("Unable to start operator for 1 or more namespace", ar.cause());
                            System.exit(1);
                        }
                    });
                } else {
                    LOGGER.error("Failed to gather environment facts", pfa.cause());
                    System.exit(1);
                }
            });
        } else  {
            LOGGER.error("Failed to create Cluster Roles", crs.cause());
            System.exit(1);
        }
    });
}
```

以上为cluster operator启动的流程，下来一一看下上面代码中所引用的方法

```java
// 看下frommap这个方法
ClusterOperatorConfig config = ClusterOperatorConfig.fromMap(System.getenv())
```

fromMap()方法获取所有环境变量

```java
    public static ClusterOperatorConfig fromMap(Map<String, String> map) {
        // 对于已经过时不用的环境变量警告
        warningsForRemovedEndVars(map);
        // 对以下四个环境变量的值进行验证
        KafkaVersion.Lookup lookup = parseKafkaVersions(
          map.get(STRIMZI_KAFKA_IMAGES), 
          map.get(STRIMZI_KAFKA_CONNECT_IMAGES), 
          map.get(STRIMZI_KAFKA_MIRROR_MAKER_IMAGES), 
          map.get(STRIMZI_KAFKA_MIRROR_MAKER_2_IMAGES));
        // 返回fromMap方法
        return fromMap(map, lookup);
    }
```

warningsForRemovedEndVars(map)方法，比较简单STRIMZI_DEFAULT_TLS_SIDECAR_KAFKA_IMAGE，STRIMZI_DEFAULT_TLS_SIDECAR_CRUISE_CONTROL_IMAGE在0.30.x版本被弃用，所以这里打了些日志警告

```java
private static void warningsForRemovedEndVars(Map<String, String> map) {
    if (map.containsKey(STRIMZI_DEFAULT_TLS_SIDECAR_KAFKA_IMAGE))    {
        LOGGER.warn("Kafka TLS sidecar container has been removed and the environment variable {} is not used anymore. " +
                "You can remove it from the Strimzi Cluster Operator deployment.", STRIMZI_DEFAULT_TLS_SIDECAR_KAFKA_IMAGE);
    }
    if (map.containsKey(STRIMZI_DEFAULT_TLS_SIDECAR_CRUISE_CONTROL_IMAGE))    {
        LOGGER.warn("Cruise Control TLS sidecar container has been removed and the environment variable {} is not used anymore. " +
                "You can remove it from the Strimzi Cluster Operator deployment.", STRIMZI_DEFAULT_TLS_SIDECAR_CRUISE_CONTROL_IMAGE);
    }
}
```

parseKafkaVersions()方法不深究了我看了下，就是对image格式进行了验证，同时还对这四个镜像的版本进行了验证

fromMap()方法

```java
public static ClusterOperatorConfig fromMap(Map<String, String> map, KafkaVersion.Lookup lookup) {
    // 以以下环境变量的值构建出config，如果没有值则给默认
    Set<String> namespaces = parseNamespaceList(map.get(STRIMZI_NAMESPACE));
    long reconciliationInterval = parseReconciliationInterval(map.get(STRIMZI_FULL_RECONCILIATION_INTERVAL_MS));
    long operationTimeout = parseTimeout(map.get(STRIMZI_OPERATION_TIMEOUT_MS), DEFAULT_OPERATION_TIMEOUT_MS);
    long connectBuildTimeout = parseTimeout(map.get(STRIMZI_CONNECT_BUILD_TIMEOUT_MS), DEFAULT_CONNECT_BUILD_TIMEOUT_MS);
    boolean createClusterRoles = parseBoolean(map.get(STRIMZI_CREATE_CLUSTER_ROLES), DEFAULT_CREATE_CLUSTER_ROLES);
    boolean networkPolicyGeneration = parseBoolean(map.get(STRIMZI_NETWORK_POLICY_GENERATION), DEFAULT_NETWORK_POLICY_GENERATION);
    ImagePullPolicy imagePullPolicy = parseImagePullPolicy(map.get(STRIMZI_IMAGE_PULL_POLICY));
    List<LocalObjectReference> imagePullSecrets = parseImagePullSecrets(map.get(STRIMZI_IMAGE_PULL_SECRETS));
    String operatorNamespace = map.get(STRIMZI_OPERATOR_NAMESPACE);
    Labels operatorNamespaceLabels = parseLabels(map, STRIMZI_OPERATOR_NAMESPACE_LABELS);
    Labels customResourceSelector = parseLabels(map, STRIMZI_CUSTOM_RESOURCE_SELECTOR);
    String featureGates = map.getOrDefault(STRIMZI_FEATURE_GATES, "");
    int operationsThreadPoolSize = parseInt(map.get(STRIMZI_OPERATIONS_THREAD_POOL_SIZE), DEFAULT_OPERATIONS_THREAD_POOL_SIZE);
    int zkAdminSessionTimeout = parseInt(map.get(STRIMZI_ZOOKEEPER_ADMIN_SESSION_TIMEOUT_MS), DEFAULT_ZOOKEEPER_ADMIN_SESSION_TIMEOUT_MS);
    int dnsCacheTtlSec = parseInt(map.get(STRIMZI_DNS_CACHE_TTL), DEFAULT_DNS_CACHE_TTL);
    boolean podSetReconciliationOnly = parseBoolean(map.get(STRIMZI_POD_SET_RECONCILIATION_ONLY), DEFAULT_POD_SET_RECONCILIATION_ONLY);
    int podSetControllerWorkQueueSize = parseInt(map.get(STRIMZI_POD_SET_CONTROLLER_WORK_QUEUE_SIZE), DEFAULT_POD_SET_CONTROLLER_WORK_QUEUE_SIZE);

    //Use default to prevent existing installations breaking if CO pod template not modified to pass through pod name
    String operatorName = map.getOrDefault(STRIMZI_OPERATOR_NAME, DEFAULT_OPERATOR_NAME);

    return new ClusterOperatorConfig(
            namespaces,
            reconciliationInterval,
            operationTimeout,
            connectBuildTimeout,
            createClusterRoles,
            networkPolicyGeneration,
            lookup,
            imagePullPolicy,
            imagePullSecrets,
            operatorNamespace,
            operatorNamespaceLabels,
            customResourceSelector,
            featureGates,
            operationsThreadPoolSize,
            zkAdminSessionTimeout,
            dnsCacheTtlSec,
            podSetReconciliationOnly,
            podSetControllerWorkQueueSize,
            operatorName);
}
```

maybeCreateClusterRoles()方法

```java
boolean createClusterRoles = parseBoolean(map.get(STRIMZI_CREATE_CLUSTER_ROLES), DEFAULT_CREATE_CLUSTER_ROLES);
```

```java
/*test*/ static Future<Void> maybeCreateClusterRoles(Vertx vertx, ClusterOperatorConfig config, KubernetesClient client)  {
    // 查看配置中STRIMZI_CREATE_CLUSTER_ROLES环境变量，如果为true
    if (config.isCreateClusterRoles()) {
        @SuppressWarnings({ "rawtypes" })
        List<Future> futures = new ArrayList<>();
        // 新建clusterRoleOperator
        ClusterRoleOperator cro = new ClusterRoleOperator(vertx, client);
				// 构建一个map，使用本身的clusterrole编排文件
        Map<String, String> clusterRoles = new HashMap<>(6);
        clusterRoles.put("strimzi-cluster-operator-namespaced", "020-ClusterRole-strimzi-cluster-operator-role.yaml");
        clusterRoles.put("strimzi-cluster-operator-global", "021-ClusterRole-strimzi-cluster-operator-role.yaml");
        clusterRoles.put("strimzi-kafka-broker", "030-ClusterRole-strimzi-kafka-broker.yaml");
        clusterRoles.put("strimzi-entity-operator", "031-ClusterRole-strimzi-entity-operator.yaml");
        clusterRoles.put("strimzi-kafka-client", "033-ClusterRole-strimzi-kafka-client.yaml");
				// 这里是调用一个reconcile方法，对deploy形式创建的operator进行reconcille，具体的调和方式是如果传入了需desired(期望状态),则调和方式为没有就创建，有的话就patch，如果没有传入则删除。
        for (Map.Entry<String, String> clusterRole : clusterRoles.entrySet()) {
            LOGGER.info("Creating cluster role {}", clusterRole.getKey());

            try (BufferedReader br = new BufferedReader(
                    new InputStreamReader(Objects.requireNonNull(Main.class.getResourceAsStream("/cluster-roles/" + clusterRole.getValue())),
                            StandardCharsets.UTF_8))) {
                String yaml = br.lines().collect(Collectors.joining(System.lineSeparator()));
                ClusterRole role = ClusterRoleOperator.convertYamlToClusterRole(yaml);
                @SuppressWarnings({ "rawtypes" })
                Future fut = cro.reconcile(new Reconciliation("start-cluster-operator", "Deployment", config.getOperatorNamespace(), "cluster-operator"), role.getMetadata().getName(), role);
                futures.add(fut);
            } catch (IOException e) {
                LOGGER.error("Failed to create Cluster Roles.", e);
                throw new RuntimeException(e);
            }

        }
				
        Promise<Void> returnPromise = Promise.promise();
        CompositeFuture.all(futures).onComplete(res -> {
            if (res.succeeded())    {
                returnPromise.complete();
            } else  {
                returnPromise.fail("Failed to create Cluster Roles.");
            }
        });

        return returnPromise.future();
    } else {
        return Future.succeededFuture();
    }
}
```

该方法根据是否创建clusterRole来patch deploy模式创建的operator控制器,如果创建成功，则跑run方法,看下run方法

```java
static CompositeFuture run(Vertx vertx, KubernetesClient client, PlatformFeaturesAvailability pfa, ClusterOperatorConfig config) {
    Util.printEnvInfo();

    ResourceOperatorSupplier resourceOperatorSupplier = new ResourceOperatorSupplier(
            vertx,
            client,
            pfa,
            config.getOperationTimeoutMs(),
            config.getOperatorName()
    );
		
    KafkaAssemblyOperator kafkaClusterOperations = null;
    KafkaConnectAssemblyOperator kafkaConnectClusterOperations = null;
    KafkaMirrorMaker2AssemblyOperator kafkaMirrorMaker2AssemblyOperator = null;
    KafkaMirrorMakerAssemblyOperator kafkaMirrorMakerAssemblyOperator = null;
    KafkaBridgeAssemblyOperator kafkaBridgeAssemblyOperator = null;
    KafkaRebalanceAssemblyOperator kafkaRebalanceAssemblyOperator = null;
		// 是否开启了podset 没有开启的话，构建kafka，kafkaconnect，kafkamirrmaker2 kafkabridge等控制器
    // boolean podSetReconciliationOnly = parseBoolean(map.get(STRIMZI_POD_SET_RECONCILIATION_ONLY), DEFAULT_POD_SET_RECONCILIATION_ONLY);
    if (!config.isPodSetReconciliationOnly()) {
        OpenSslCertManager certManager = new OpenSslCertManager();
        PasswordGenerator passwordGenerator = new PasswordGenerator(12,
                "abcdefghijklmnopqrstuvwxyz" +
                        "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
                "abcdefghijklmnopqrstuvwxyz" +
                        "ABCDEFGHIJKLMNOPQRSTUVWXYZ" +
                        "0123456789");

        kafkaClusterOperations = new KafkaAssemblyOperator(vertx, pfa, certManager, passwordGenerator, resourceOperatorSupplier, config);
        kafkaConnectClusterOperations = new KafkaConnectAssemblyOperator(vertx, pfa, resourceOperatorSupplier, config);
        kafkaMirrorMaker2AssemblyOperator = new KafkaMirrorMaker2AssemblyOperator(vertx, pfa, resourceOperatorSupplier, config);
        kafkaMirrorMakerAssemblyOperator = new KafkaMirrorMakerAssemblyOperator(vertx, pfa, certManager, passwordGenerator, resourceOperatorSupplier, config);
        kafkaBridgeAssemblyOperator = new KafkaBridgeAssemblyOperator(vertx, pfa, certManager, passwordGenerator, resourceOperatorSupplier, config);
        kafkaRebalanceAssemblyOperator = new KafkaRebalanceAssemblyOperator(vertx, resourceOperatorSupplier, config);
    }
		// 上述这些控制器构成cluster operator 创建他
    @SuppressWarnings({ "rawtypes" })
    List<Future> futures = new ArrayList<>(config.getNamespaces().size());
    for (String namespace : config.getNamespaces()) {
        Promise<String> prom = Promise.promise();
        futures.add(prom.future());
        ClusterOperator operator = new ClusterOperator(namespace,
                config,
                client,
                kafkaClusterOperations,
                kafkaConnectClusterOperations,
                kafkaMirrorMakerAssemblyOperator,
                kafkaMirrorMaker2AssemblyOperator,
                kafkaBridgeAssemblyOperator,
                kafkaRebalanceAssemblyOperator,
                resourceOperatorSupplier);
        vertx.deployVerticle(operator,
            res -> {
                if (res.succeeded()) {
                    if (config.getCustomResourceSelector() != null) {
                        LOGGER.info("Cluster Operator verticle started in namespace {} with label selector {}", namespace, config.getCustomResourceSelector());
                    } else {
                        LOGGER.info("Cluster Operator verticle started in namespace {} without label selector", namespace);
                    }
                } else {
                    LOGGER.error("Cluster Operator verticle in namespace {} failed to start", namespace, res.cause());
                    System.exit(1);
                }
                prom.handle(res);
            });
    }
    return CompositeFuture.join(futures);
}
```

上述就是cluster operator的启动逻辑，下来我们看下kafka operator的一个调和逻辑

ClusterOperator启动通过watcher监听各obj事件，对于MODIFIED类型的事件调用reconcile方法开始调和，error或者default则使用reconcileAll方法调和

```java
public void eventReceived(Action action, T resource) {
    String name = resource.getMetadata().getName();
    String namespace = resource.getMetadata().getNamespace();
    switch (action) {
        case ADDED:
        case DELETED:
        case MODIFIED:
            Reconciliation reconciliation = new Reconciliation("watch", operator.kind(), namespace, name);
            LOGGER.infoCr(reconciliation, "{} {} in namespace {} was {}", operator.kind(), name, namespace, action);
            operator.reconcile(reconciliation);
            break;
        case ERROR:
            LOGGER.errorCr(new Reconciliation("watch", operator.kind(), namespace, name), "Failed {} {} in namespace{} ", operator.kind(), name, namespace);
            operator.reconcileAll("watch error", namespace, ignored -> { });
            break;
        default:
            LOGGER.errorCr(new Reconciliation("watch", operator.kind(), namespace, name), "Unknown action: {} in namespace {}", name, namespace);
            operator.reconcileAll("watch unknown", namespace, ignored -> { });
    }
}
```

先看下reconcileAll()方法

```java
default void reconcileAll(String trigger, String namespace, Handler<AsyncResult<Void>> handler) {
  // 调用allResourceNames()方法，如果成功，则reconcile这些通过allresourcename方法获取到的oj
  allResourceNames(namespace).onComplete(ar -> {
        if (ar.succeeded()) {
            reconcileThese(trigger, ar.result(), namespace, handler);
            periodicReconciliationsCounter(namespace).increment();
        } else {
            handler.handle(ar.map((Void) null));
        }
    });
}
```

看下allResourceNames()方法,如下，就是根据selector选择出自身的需要调和的obj

```java
public Future<Set<NamespaceAndName>> allResourceNames(String namespace) {
    return resourceOperator.listAsync(namespace, selector())
            .map(resourceList ->
                    resourceList.stream()
                            .map(resource -> new NamespaceAndName(resource.getMetadata().getNamespace(), resource.getMetadata().getName()))
                            .collect(Collectors.toSet()));
}
```

selector()方法如下：

```java
public Optional<LabelSelector> selector() {
    return selector;
}
```

主要看下reconcileThese()方法

```java
default void reconcileThese(String trigger, Set<NamespaceAndName> desiredNames, String namespace, Handler<AsyncResult<Void>> handler) {
  // 如果是全局的namespace,设置一个要调和的资源hash以及暂停调和的资源hash  
  if (namespace.equals("*")) {
        resetCounters();
    } else {
        resourceCounter(namespace).set(0);
        pausedResourceCounter(namespace).set(0);
    }
		// 对资源进行调和
    if (desiredNames.size() > 0) {
        List<Future> futures = new ArrayList<>();
        for (NamespaceAndName resourceRef : desiredNames) {
            // 加入资源hash
            resourceCounter(resourceRef.getNamespace()).getAndIncrement();
            Reconciliation reconciliation = new Reconciliation(trigger, kind(), resourceRef.getNamespace(), resourceRef.getName());
            futures.add(reconcile(reconciliation));
        }
        CompositeFuture.join(futures).map((Void) null).onComplete(handler);
    } else {
        handler.handle(Future.succeededFuture());
    }
}
```

看下reconcile()方法

```java
// 方法很长，总体逻辑如下： 1. 根据注解判断是否是暂停调度，根据cr.spec更新cr的condition和status 2. 调用createOrUpdate接口
public final Future<Void> reconcile(Reconciliation reconciliation) {}
```

createOrUpdate接口

<div align=center>
<img src="/images/6.png" />
</div>

可以看到kafka的几个CRD基本都实现了createOperator方法，先看下Cluster Operator的createOrUPdate实现

```java
public Future<KafkaStatus> createOrUpdate(Reconciliation reconciliation, Kafka kafkaAssembly) {
    Promise<KafkaStatus> createOrUpdatePromise = Promise.promise();
    ReconciliationState reconcileState = createReconciliationState(reconciliation, kafkaAssembly);
		// 进来主要是这个reconcile方法
    reconcile(reconcileState).onComplete(reconcileResult -> {....}
```

```java
Future<Void> reconcile(ReconciliationState reconcileState)  {
    Promise<Void> chainPromise = Promise.promise();

    // 验证目前在KRaft模式下不支持的功能,如果cr的spec中开启了kraft
    if (featureGates.useKRaftEnabled()) {
        try {
            KRaftUtils.validateKafkaCrForKRaft(reconcileState.kafkaAssembly.getSpec());
        } catch (InvalidResourceException e)    {
            return Future.failedFuture(e);
        }
    }

    reconcileState.initialStatus()
            // 创建CaReconciler实例，并调和客户和集群的CA。产生的CA被存储在在ReconciliationState中，并在以后用于对操作数进行调节
            .compose(state -> state.reconcileCas(this::dateSupplier))
            // 
            .compose(state -> state.versionChange())

            // Run reconciliations of the different components
            .compose(state -> featureGates.useKRaftEnabled() ? Future.succeededFuture(state) : state.reconcileZooKeeper(this::dateSupplier))
            .compose(state -> state.reconcileKafka(this::dateSupplier))
            .compose(state -> state.reconcileEntityOperator(this::dateSupplier))
            .compose(state -> state.reconcileCruiseControl(this::dateSupplier))
            .compose(state -> state.reconcileKafkaExporter(this::dateSupplier))
            .compose(state -> state.reconcileJmxTrans())

            // Finish the reconciliation
            .map((Void) null)
            .onComplete(chainPromise);

    return chainPromise.future();
}
```

cluster operator的几个调和步骤，一个一个看，先看下reconcileCas()

```java
// reconcileCas创建一个careconciler调用他的reconcile方法将结果放入ReconciliationState中
Future<ReconciliationState> reconcileCas(Supplier<Date> dateSupplier)    {
    return caReconciler()
            .reconcile(dateSupplier)
            .compose(cas -> {
                this.clusterCa = cas.clusterCa;
                this.clientsCa = cas.clientsCa;
                return Future.succeededFuture(this);
            });
}
```

看下caReconciler()方法，是一些前置条件,太长，主要是创建出clientCa与clusterCa以secret的方式，源码地址为：strimzi-kafka-operator/cluster-operator/src/main/java/io/strimzi/operator/cluster/operator/assembly/CaReconciler.java。

```java
clusterCa = new ClusterCa(reconciliation, certManager, passwordGenerator, reconciliation.name(), clusterCaCertSecret,
        clusterCaKeySecret,
        ModelUtils.getCertificateValidity(clusterCaConfig),
        ModelUtils.getRenewalDays(clusterCaConfig),
        clusterCaConfig == null || clusterCaConfig.isGenerateCertificateAuthority(), clusterCaConfig != null ? clusterCaConfig.getCertificateExpirationPolicy() : null);
clusterCa.initCaSecrets(clusterSecrets);
clusterCa.createRenewOrReplace(
        reconciliation.namespace(), reconciliation.name(), caLabels,
        clusterCaCertLabels, clusterCaCertAnnotations,
        clusterCaConfig != null && !clusterCaConfig.isGenerateSecretOwnerReference() ? null : ownerRef,
        Util.isMaintenanceTimeWindowsSatisfied(reconciliation, maintenanceWindows, dateSupplier));

// When we are not supposed to generate the CA, but it does not exist, we should just throw an error
checkCustomCaSecret(clientsCaConfig, clientsCaCertSecret, clientsCaKeySecret, "Clients CA");

clientsCa = new ClientsCa(reconciliation, certManager,
        passwordGenerator, clientsCaCertName,
        clientsCaCertSecret, clientsCaKeyName,
        clientsCaKeySecret,
        ModelUtils.getCertificateValidity(clientsCaConfig),
        ModelUtils.getRenewalDays(clientsCaConfig),
        clientsCaConfig == null || clientsCaConfig.isGenerateCertificateAuthority(),
        clientsCaConfig != null ? clientsCaConfig.getCertificateExpirationPolicy() : null);
clientsCa.initBrokerSecret(brokersSecret);
clientsCa.createRenewOrReplace(reconciliation.namespace(), reconciliation.name(),
        caLabels, Map.of(), Map.of(),
        clientsCaConfig != null && !clientsCaConfig.isGenerateSecretOwnerReference() ? null : ownerRef,
        Util.isMaintenanceTimeWindowsSatisfied(reconciliation, maintenanceWindows, dateSupplier));
```

看下caReconciler().reconcile()，这是caReconcile调和过程,这边主要是调和ca保证他的可用性

```java
public Future<CaReconciliationResult> reconcile(Supplier<Date> dateSupplier)    {
    return reconcileCas(dateSupplier)
            .compose(i -> clusterOperatorSecret(dateSupplier))
            .compose(i -> rollingUpdateForNewCaKey())
            .compose(i -> maybeRemoveOldClusterCaCertificates())
            .map(i -> new CaReconciliationResult(clusterCa, clientsCa));
}
```

看下第二步state.versionChange(),他也是同样的查看他的reconcile()方法

```java
// 从Kubernetes资源中收集信息并创建KafkaVersionChange实例，描述在此调和的版本变化,主要就是从kafka的pod中注解获取strimzi.io/kafka-version的值
public Future<KafkaVersionChange> reconcile()    {
    // 获取sts或者strimizepodset中配置kafka的版本
    return getVersionFromController()
            // 获取所有的kafka pod
            .compose(i -> getPods())
            // 根据从Kubernetes收集的信息，检测当前和期望的Kafka版本
            .compose(this::detectToAndFromVersions)
            // 做版本变更
            .compose(i -> prepareVersionChange());
}
```

该方法主要是用来处理kafka版本升级的

继续看下一步，featureGates.useKRaftEnabled() ? Future.succeededFuture(state) : state.reconcileZooKeeper(this::dateSupplier)

这里主要是判断是否开了kraft，开了的话这一步直接成功，没开的话就调和zookeeper

看下reconcileZooKeeper()

```java
Future<ReconciliationState> reconcileZooKeeper(Supplier<Date> dateSupplier)    {
  // zooKeeperReconciler()构建zookeeperReconcile方法
    return zooKeeperReconciler()
            // zookeeper调和
            .compose(reconciler -> reconciler.reconcile(kafkaStatus, dateSupplier))
            .map(this);
}
```

看下zookeeper调和步骤，这边不细说了只说他的调和流程，源码在：strimzi-kafka-operator/cluster-operator/src/main/java/io/strimzi/operator/cluster/operator/assembly/ZooKeeperReconciler.java

```java
public Future<Void> reconcile(KafkaStatus kafkaStatus, Supplier<Date> dateSupplier)    {
    return modelWarnings(kafkaStatus)
            // jmx secret创建
            .compose(i -> jmxSecret())
            // 对原来pod的清除逻辑
            .compose(i -> manualPodCleaning())
            // networkPolicy创建
            .compose(i -> networkPolicy())
            // 是否需要滚动更新
            .compose(i -> manualRollingUpdate())
            // zookeeper log改变
            .compose(i -> logVersionChange())
            // zookeeper pod sa
            .compose(i -> serviceAccount())
            // pvc
            .compose(i -> pvcs())
            // service
            .compose(i -> service())
            // 无头服务svc
            .compose(i -> headlessService())
            // casecret
            .compose(i -> certificateSecret(dateSupplier))
            // 日志和metric的配置
            .compose(i -> loggingAndMetricsConfigMap())
            // pdb pod高可用
            .compose(i -> podDisruptionBudget())
            .compose(i -> podDisruptionBudgetV1Beta1())
            // zookeeper sts
            .compose(i -> statefulSet())
            // podset对pod进行定制化
            .compose(i -> podSet())
            // 缩容
            .compose(i -> scaleDown())
            // 更新
            .compose(i -> rollingUpdate())
            // 检查pod是否ready
            .compose(i -> podsReady())
            // 扩容
            .compose(i -> scaleUp())
            // 扩缩容检查
            .compose(i -> scalingCheck())
            // ep检查
            .compose(i -> serviceEndpointsReady())
            // 无头服务ep检查
            .compose(i -> headlessServiceEndpointsReady())
            // pvc是否删除
            .compose(i -> deletePersistentClaims());
}
```

调和完zookeeper调和kafka，看下reconcileKafka方法

```java
Future<ReconciliationState> reconcileKafka(Supplier<Date> dateSupplier)    {
   // 同样的，首先构建kafka reconcile，然后调用他的reconcile
    return kafkaReconciler()
            .compose(reconciler -> reconciler.reconcile(kafkaStatus, dateSupplier))
            .map(this);
}
```

kafkaReconciler().reconcile方法

```java
public Future<Void> reconcile(KafkaStatus kafkaStatus, Supplier<Date> dateSupplier)    {
    return modelWarnings(kafkaStatus)
            // 清理旧的pod
            .compose(i -> manualPodCleaning())
            // pod网络networkpolicy
            .compose(i -> networkPolicy())
            // 滚动更新逻辑
            .compose(i -> manualRollingUpdate())
            // pvc
            .compose(i -> pvcs())
            // sa
            .compose(i -> serviceAccount())
            // 初始化clusterrolebinding
            .compose(i -> initClusterRoleBinding())
            // 缩容
            .compose(i -> scaleDown())
            // kafka监听端口配置
            .compose(i -> listeners())
            // ca
            .compose(i -> certificateSecret(dateSupplier))
            // broker的配置
            .compose(i -> brokerConfigurationConfigMaps())
            // jmx secret
            .compose(i -> jmxSecret())
            // kafka pod高可用
            .compose(i -> podDisruptionBudget())
            .compose(i -> podDisruptionBudgetV1Beta1())
            // kafka sts
            .compose(i -> statefulSet())
            // kafka pod高级配置
            .compose(i -> podSet())
            // 存储卷的更新
            .compose(i -> rollToAddOrRemoveVolumes())
            // 滚动更新kafka服务
            .compose(i -> rollingUpdate())
            // 扩容
            .compose(i -> scaleUp())
            // 检查pod是否ready
            .compose(i -> podsReady())
            // 检查svc ep是否ready
            .compose(i -> serviceEndpointsReady())
            // 检查svc headless svc ep是否ready
            .compose(i -> headlessServiceEndpointsReady())
            // 更新kafka status使用clusterId
            .compose(i -> clusterId(kafkaStatus))
            // PersistentClaims类型的pvc清理
            .compose(i -> deletePersistentClaims())
            // broker配置清理
            .compose(i -> brokerConfigurationConfigMapsCleanup())
            // node port类型的监听端口跟新
            .compose(i -> nodePortExternalListenerStatus())
            // 将kafka 监听端口添加到kafka status中
            .compose(i -> addListenersToKafkaStatus(kafkaStatus));
}
```

kafka调和如上，跳过reconcileEntityOperator()调和，因为reconcileEntityOperator会启动topic Operator和user Operator，不再cluster operator的范围内他们具有各自的控制器

继续看reconcileCruiseControl()调和，CruiseControl是linked提供一个对体量非常庞大的kafka服务提供的优化策略平台，他会根据当前kafka集群提供优化建议等功能

```java
Future<ReconciliationState> reconcileCruiseControl(Supplier<Date> dateSupplier)    {
  // 同样的，构建cruiseControlReconciler,调用他的reconcile方法
  return cruiseControlReconciler()
            .reconcile(pfa.isOpenshift(), imagePullPolicy, imagePullSecrets, dateSupplier)
            .map(this);
}
```

看下cruiseControlReconciler().reconcile()

```java
public Future<Void> reconcile(boolean isOpenShift, ImagePullPolicy imagePullPolicy, List<LocalObjectReference> imagePullSecrets, Supplier<Date> dateSupplier)    {
    return networkPolicy()
            // sa配置
            .compose(i -> serviceAccount())
            // 监控以及日志配置
            .compose(i -> metricsAndLoggingConfigMap())
            // 与kafka通信的ca配置
            .compose(i -> certificatesSecret(dateSupplier))
            // api secret
            .compose(i -> apiSecret())
            // svc
            .compose(i -> service())
            // deploy部署
            .compose(i -> deployment(isOpenShift, imagePullPolicy, imagePullSecrets))
            // 健康检查
            .compose(i -> waitForDeploymentReadiness());
}
```

继续看像下看reconcileKafkaExporter()调和

```java
Future<ReconciliationState> reconcileKafkaExporter(Supplier<Date> dateSupplier)    {
    return kafkaExporterReconciler()
            .reconcile(pfa.isOpenshift(), imagePullPolicy, imagePullSecrets, dateSupplier)
            .map(this);
}
```

同样的，看kafkaExporterReconciler().reconcile()方法

```java
public Future<Void> reconcile(boolean isOpenShift, ImagePullPolicy imagePullPolicy, List<LocalObjectReference> imagePullSecrets, Supplier<Date> dateSupplier)    {
    return serviceAccount()
            // 与kafka通信的ca证书
            .compose(i -> certificatesSecret(dateSupplier))
            // deploy部署
            .compose(i -> deployment(isOpenShift, imagePullPolicy, imagePullSecrets))
            // 健康检查
            .compose(i -> waitForDeploymentReadiness());
}
```

reconcileJmxTrans()方法

```java
Future<ReconciliationState> reconcileJmxTrans()    {
    return jmxTransReconciler()
            .reconcile(imagePullPolicy, imagePullSecrets)
            .map(this);
}
```

看reconcileJmxTrans().reconcile()方法

```java
public Future<Void> reconcile(ImagePullPolicy imagePullPolicy, List<LocalObjectReference> imagePullSecrets)    {
    return serviceAccount()
            // 构建configmap
            .compose(i -> configMap())
            // deploy部署
            .compose(i -> deployment(imagePullPolicy, imagePullSecrets))
            // 健康检查
            .compose(i -> waitForDeploymentReadiness());
}
```

整个cluster Operator的逻辑就是这样，总的来说还是比较复杂的，但是整体脉络理清了，遇到问题便可对症下药，本人没接触过java，看kafka Operator源码，本篇耗时一天，要不就是java简单，要不就是本人牛逼，当然主要也是没有细看的原因，感觉语言都是相通的，整体脉络应该就是这样，有些方法接口java中的关键字，我都不知道，大部分靠蒙，但是蒙下来能圆上，我感觉就算是蒙对啦，哈哈。
