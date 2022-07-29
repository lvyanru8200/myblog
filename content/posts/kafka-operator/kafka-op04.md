---
title: "Kafka Op04"
subtitle: ""
date: 2022-07-28T11:18:14+08:00
lastmod: 2022-07-28T11:18:14+08:00
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

#### Kafka Operator代码阅读04--KafkaMirrorMaker CRD逻辑

#### 本文主旨：

- [strimize-kafka-opertaor](https://github.com/strimzi/strimzi-kafka-operator) KafkaMirrorMaker CRD 代码阅读

#### MirrorMaker介绍

​     Kakfa MirrorMaker是Kafka 官方提供的跨数据中心的流数据同步方案。其实现原理，其实就是通过从Source Cluster消费消息然后将消息生产到Target Cluster，即普通的消息生产和消费。用户只要通过简单的consumer配置和producer配置，然后启动Mirror，就可以实现准实时的数据同步。

#### MirrorMaker Operator

通过01文章可以看出clusterOperator的run方法会启动各种cr的调和，mirrormaker直接看createOrUpdate方法

```java
protected Future<KafkaMirrorMakerStatus> createOrUpdate(Reconciliation reconciliation, KafkaMirrorMaker assemblyResource) {
    String namespace = reconciliation.namespace();
    KafkaMirrorMakerCluster mirror;
    KafkaMirrorMakerStatus kafkaMirrorMakerStatus = new KafkaMirrorMakerStatus();

    try {
        mirror = KafkaMirrorMakerCluster.fromCrd(reconciliation, assemblyResource, versions);
    } catch (Exception e) {
        LOGGER.warnCr(reconciliation, e);
        StatusUtils.setStatusConditionAndObservedGeneration(assemblyResource, kafkaMirrorMakerStatus, Future.failedFuture(e));
        return Future.failedFuture(new ReconciliationException(kafkaMirrorMakerStatus, e));
    }

    Map<String, String> annotations = new HashMap<>(1);
		// consumer的认证配置
    KafkaClientAuthentication authConsumer = assemblyResource.getSpec().getConsumer().getAuthentication();
    List<CertSecretSource> trustedCertificatesConsumer = assemblyResource.getSpec().getConsumer().getTls() == null ? Collections.emptyList() : assemblyResource.getSpec().getConsumer().getTls().getTrustedCertificates();
    // producer的认证配置
    KafkaClientAuthentication authProducer = assemblyResource.getSpec().getProducer().getAuthentication();
    List<CertSecretSource> trustedCertificatesProducer = assemblyResource.getSpec().getProducer().getTls() == null ? Collections.emptyList() : assemblyResource.getSpec().getProducer().getTls().getTrustedCertificates();

    Promise<KafkaMirrorMakerStatus> createOrUpdatePromise = Promise.promise();
		// 判断mirror是否具有副本数量
    boolean mirrorHasZeroReplicas = mirror.getReplicas() == 0;

    LOGGER.debugCr(reconciliation, "Updating Kafka Mirror Maker cluster");
    mirrorMakerServiceAccount(reconciliation, namespace, mirror)
            // 判断是否要缩容
            .compose(i -> deploymentOperations.scaleDown(reconciliation, namespace, mirror.getName(), mirror.getReplicas()))
            // metrics以及日志设置
            .compose(i -> Util.metricsAndLogging(reconciliation, configMapOperations, namespace, mirror.getLogging(), mirror.getMetricsConfigInCm()))
            .compose(metricsAndLoggingCm -> {
                ConfigMap logAndMetricsConfigMap = mirror.generateMetricsAndLogConfigMap(metricsAndLoggingCm);
                annotations.put(Annotations.STRIMZI_LOGGING_ANNOTATION, logAndMetricsConfigMap.getData().get(mirror.ANCILLARY_CM_KEY_LOG_CONFIG));
                return configMapOperations.reconcile(reconciliation, namespace, mirror.getAncillaryConfigMapName(), logAndMetricsConfigMap);
            })
            // 判断pdb的版本，v1或者v1beta1
            .compose(i -> pfa.hasPodDisruptionBudgetV1() ? podDisruptionBudgetOperator.reconcile(reconciliation, namespace, mirror.getName(), mirror.generatePodDisruptionBudget()) : Future.succeededFuture())
            .compose(i -> !pfa.hasPodDisruptionBudgetV1() ? podDisruptionBudgetV1Beta1Operator.reconcile(reconciliation, namespace, mirror.getName(), mirror.generatePodDisruptionBudgetV1Beta1()) : Future.succeededFuture())
            // 连接kafka集群的auth
            .compose(i -> CompositeFuture.join(Util.authTlsHash(secretOperations, namespace, authConsumer, trustedCertificatesConsumer),
                    Util.authTlsHash(secretOperations, namespace, authProducer, trustedCertificatesProducer)))
            .compose(hashFut -> {
                if (hashFut != null) {
                    annotations.put(Annotations.ANNO_STRIMZI_AUTH_HASH, Integer.toString((int) hashFut.resultAt(0) + (int) hashFut.resultAt(1)));
                }
                return Future.succeededFuture();
            })
            // deployment创建
            .compose(i -> deploymentOperations.reconcile(reconciliation, namespace, mirror.getName(), mirror.generateDeployment(annotations, pfa.isOpenshift(), imagePullPolicy, imagePullSecrets)))
            // 扩容
            .compose(i -> deploymentOperations.scaleUp(reconciliation, namespace, mirror.getName(), mirror.getReplicas()))
            // 等待资源启动
            .compose(i -> deploymentOperations.waitForObserved(reconciliation, namespace, mirror.getName(), 1_000, operationTimeoutMs))
            // 如果有多个副本，则启动相应数量的等待线程，等待资源启动
            .compose(i -> mirrorHasZeroReplicas ? Future.succeededFuture() : deploymentOperations.readiness(reconciliation, namespace, mirror.getName(), 1_000, operationTimeoutMs))
            // 根据结果更新状态
            .onComplete(reconciliationResult -> {
                    StatusUtils.setStatusConditionAndObservedGeneration(assemblyResource, kafkaMirrorMakerStatus, reconciliationResult);

                    kafkaMirrorMakerStatus.setReplicas(mirror.getReplicas());
                    kafkaMirrorMakerStatus.setLabelSelector(mirror.getSelectorLabels().toSelectorString());

                    if (reconciliationResult.succeeded())   {
                        createOrUpdatePromise.complete(kafkaMirrorMakerStatus);
                    } else {
                        createOrUpdatePromise.fail(new ReconciliationException(kafkaMirrorMakerStatus, reconciliationResult.cause()));
                    }
            }
        );

    return createOrUpdatePromise.future();
}
```

mirrorMaker的代码逻辑比较简单，主要是因为kafka已经封装好了集群之间数据同步的功能。
