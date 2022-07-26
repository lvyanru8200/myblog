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
// 看下frommap这个fna
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
