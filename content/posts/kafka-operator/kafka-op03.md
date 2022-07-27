---
title: "Kafka Op03"
subtitle: ""
date: 2022-07-27T21:29:11+08:00
lastmod: 2022-07-27T21:29:11+08:00
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

#### Kafka Operator代码阅读03--kafkaTopic CRD逻辑

#### 本文主旨：

- [strimize-kafka-opertaor](https://github.com/strimzi/strimzi-kafka-operator) KafkaTopic CRD 代码阅读

#### Topic Operator

​	Topic Operator是一个独立的模块，他没有通过createOrUpdate方法去调和

看下Topic Operator的main方法

```java
public static void main(String[] args) {
    LOGGER.info("TopicOperator {} is starting", Main.class.getPackage().getImplementationVersion());
    Main main = new Main();
    main.run();
}
// run方法构建出topic operator所使用的config，然后deploy他，看下deploy方法
public void run() {
    Map<String, String> m = new HashMap<>(System.getenv());
    m.keySet().retainAll(Config.keyNames());
    Config config = new Config(m);
    deploy(config);
}
```

```java
private void deploy(Config config) {
    DefaultKubernetesClient kubeClient = new DefaultKubernetesClient();
    Crds.registerCustomKinds();
    VertxOptions options = new VertxOptions().setMetricsOptions(
            new MicrometerMetricsOptions()
                    .setPrometheusOptions(new VertxPrometheusOptions().setEnabled(true))
                    .setJvmMetricsEnabled(true)
                    .setEnabled(true));
    Vertx vertx = Vertx.vertx(options);

    Session session = new Session(kubeClient, config);
    vertx.deployVerticle(session, ar -> {
        if (ar.succeeded()) {
            LOGGER.info("Session deployed");
        } else {
            LOGGER.error("Error deploying Session", ar.cause());
        }
    });
}
```

deploy方法注册crd，构建metrcis，新建session，java的controller代码模式我不太懂，这里就先认为注册过后就可以监控进入调和了，看下java掉的k8s的watcher，看下他的事件监听

```java
    public void eventReceived(Action action, KafkaTopic kafkaTopic) {
      // 可以看到对kafkatopic进行监控  
      ObjectMeta metadata = kafkaTopic.getMetadata();
        Map<String, String> labels = metadata.getLabels();
        if (kafkaTopic.getSpec() != null) {
            LogContext logContext = LogContext.kubeWatch(action, kafkaTopic).withKubeTopic(kafkaTopic);
            String name = metadata.getName();
            String kind = kafkaTopic.getKind();
            if (!initReconcileFuture.isComplete()) {
                LOGGER.debugCr(logContext.toReconciliation(), "Ignoring initial event for {} {} during initial reconcile", kind, name);
                return;
            }
            if (action.equals(Action.ERROR)) {
                LOGGER.errorCr(logContext.toReconciliation(), "Watch received action=ERROR for {} {} {}", kind, name, kafkaTopic);
            } else {
                PauseAnnotationChanges pauseAnnotationChanges = pausedAnnotationChanged(kafkaTopic);
                if (action.equals(Action.DELETED) || shouldReconcile(kafkaTopic, metadata, pauseAnnotationChanges.isChanged())) {
                    if (pauseAnnotationChanges.isResourcePausedByAnno()) {
                        topicOperator.pausedTopicCounter.getAndIncrement();
                    } else if (pauseAnnotationChanges.isResourceUnpausedByAnno()) {
                        topicOperator.pausedTopicCounter.getAndDecrement();
                    }
                    LOGGER.infoCr(logContext.toReconciliation(), "event {} on resource {} generation={}, labels={}", action, name,
                            metadata.getGeneration(), labels);
                    Handler<AsyncResult<Void>> resultHandler = ar -> {
                        if (ar.succeeded()) {
                            LOGGER.infoCr(logContext.toReconciliation(), "Success processing event {} on resource {} with labels {}", action, name, labels);
                        } else {
                            String message;
                            if (ar.cause() instanceof InvalidTopicException) {
                                message = kind + " " + name + " has an invalid spec section: " + ar.cause().getMessage();
                                LOGGER.errorCr(logContext.toReconciliation(), message);

                            } else {
                                message = "Failure processing " + kind + " watch event " + action + " on resource " + name + " with labels " + labels + ": " + ar.cause().getMessage();
                                LOGGER.errorCr(logContext.toReconciliation(), message, ar.cause());
                            }
                            topicOperator.enqueue(logContext, topicOperator.new Event(logContext, kafkaTopic, message, TopicOperator.EventType.WARNING, errorResult -> {
                            }));
                        }
                    };
                    topicOperator.onResourceEvent(logContext, kafkaTopic, action).onComplete(resultHandler);
                } else {
                    LOGGER.debugCr(logContext.toReconciliation(), "Ignoring {} to {} {} because metadata.generation==status.observedGeneration", action, kind, name);
                }
            }
        }
    }
```

```java
// 看下start方法
public void start(Promise<Void> start) {
    LOGGER.info("Starting");
		// dns cache设置
    String dnsCacheTtl = System.getenv("STRIMZI_DNS_CACHE_TTL") == null ? "30" : System.getenv("STRIMZI_DNS_CACHE_TTL");
    Security.setProperty("networkaddress.cache.ttl", dnsCacheTtl);
		// 创建一个client
    this.adminClient = AdminClient.create(adminClientProperties());
    LOGGER.debug("Using AdminClient {}", adminClient);
    this.kafka = new KafkaImpl(adminClient, vertx);
    LOGGER.debug("Using Kafka {}", kafka);
    Labels labels = config.get(Config.LABELS);

    String namespace = config.get(Config.NAMESPACE);
    LOGGER.debug("Using namespace {}", namespace);
    this.k8s = new K8sImpl(vertx, kubeClient, labels, namespace);
    LOGGER.debug("Using k8s {}", k8s);

    String clientId = config.get(Config.CLIENT_ID);
    LOGGER.debug("Using client-Id {}", clientId);
		// 主要看下这里的方法
    startHealthServer(topicOperatorState)
            .onFailure(cause -> LOGGER.error("Failed to start health server", cause))
            .onSuccess(httpServer -> healthServer = httpServer)
          	// 
            .compose(ignored -> zkClientCreator.apply(vertx, config))
            .onSuccess(zookeeper -> zk = zookeeper)
            // 创建一个存储主题的topic
            .compose(zk -> createTopicStoreAsync(zk, config))
            .onSuccess(topicStore -> LOGGER.debug("Using TopicStore {}", topicStore))
            // 创建topicOperator和zkWatcher
            .compose(topicStore -> createTopicOperatorAndZkWatchers(labels, namespace, topicStore))
            // 创建k8s资源的watcher
            .compose(this::createK8sWatcher)
            // 开始调和topic
            .onSuccess(this::createPeriodicReconcileTrigger)
            .onSuccess(ignored -> {
                start.complete();
                topicOperatorState.setReady(true);
                LOGGER.info("Started");
            })
            .onFailure(cause -> {
                topicOperatorState.setAlive(false);
                start.fail(cause);
                LOGGER.error("Topic operator start up failed, cause was", cause);
            });
}
```

看下k8sWatcher()

```java
private Future<Promise<Void>> createK8sWatcher(TopicOperator topicOperator) {
    return executor.executeBlocking(blockingPromise -> {
        Promise<Void> initReconcilePromise = Promise.promise();
        watcher = new K8sTopicWatcher(topicOperator, initReconcilePromise.future(), this::startWatcher);
        LOGGER.debug("Starting watcher");
        startWatcher().onSuccess(v -> blockingPromise.complete(initReconcilePromise));
    });
}
```

startWatcher()方法

```java
Future<Void> startWatcher() {
    // 根据标签选择要监控的topic资源
    Promise<Void> promise = Promise.promise();
    try {
        LOGGER.debug("Watching KafkaTopics matching {}", config.get(Config.LABELS).labels());

        Session.this.topicWatch = kubeClient.resources(KafkaTopic.class, KafkaTopicList.class)
                .inNamespace(config.get(Config.NAMESPACE)).withLabels(config.get(Config.LABELS).labels()).watch(watcher);
        LOGGER.debug("Watching setup");
        promise.complete();
    } catch (Throwable t) {
        promise.fail(t);
    }
    return promise.future();
}
```

看下createTopicOperatorAndZkWatchers()方法，createTopicStoreAsync()是在kafka实例中创建两个用于存储topic的topic

```java
private Future<TopicOperator> createTopicOperatorAndZkWatchers(Labels labels, String namespace, TopicStore topicStore) {
    // 构建topic operator/topicConfigWatcher等接口，然后启动topicwatcher
    topicOperator = new TopicOperator(vertx, kafka, k8s, topicStore, labels, namespace, config, new MicrometerMetricsProvider());
    LOGGER.debug("Using Operator {}", topicOperator);

    topicConfigsWatcher = new TopicConfigsWatcher(topicOperator);
    LOGGER.debug("Using TopicConfigsWatcher {}", topicConfigsWatcher);
    topicWatcher = new ZkTopicWatcher(topicOperator);
    LOGGER.debug("Using TopicWatcher {}", topicWatcher);
    topicsWatcher = new ZkTopicsWatcher(topicOperator, topicConfigsWatcher, topicWatcher);
    LOGGER.debug("Using TopicsWatcher {}", topicsWatcher);
    topicsWatcher.start(zk);
    return Future.succeededFuture(topicOperator);
}
```

看下topicsWatcher.start(zk)方法

```java
void start(Zk zk) {
    synchronized (this) {
        children = null;
    }
    tcw.start(zk);
    tw.start(zk);
    zk.watchChildren(TOPICS_ZNODE, new ChildrenWatchHandler(zk)).<Void>compose(zk2 -> {
        zk.children(TOPICS_ZNODE, childResult -> {
            if (childResult.failed()) {
                LOGGER.errorOp("Error on znode {} children", TOPICS_ZNODE, childResult.cause());
                return;
            }
            List<String> result = childResult.result();
            LOGGER.debugOp("Setting initial children {}", result);
            synchronized (this) {
                this.children = result;
            }
            // Start watching existing children for config and partition changes
            for (String child : result) {
                tcw.addChild(child);
                tw.addChild(child);
            }
            this.state = 1;
        });
        return Future.succeededFuture();
    });
}
```

createPeriodicReconcileTrigger()方法开始进行调和

```java
private void createPeriodicReconcileTrigger(Promise<Void> initReconcilePromise) {
    final Long interval = config.get(Config.FULL_RECONCILIATION_INTERVAL_MS);
    Handler<Long> periodic = new Handler<>() {
        @Override
        public void handle(Long oldTimerId) {
            if (!stopped) {
                timerId = null;
                boolean isInitialReconcile = oldTimerId == null;
                topicOperator.getPeriodicReconciliationsCounter().increment();
                topicOperator.reconcileAllTopics(isInitialReconcile ? "initial " : "periodic ").onComplete(result -> {
                    if (isInitialReconcile) {
                        initReconcilePromise.complete();
                    }
                    if (!stopped) {
                        timerId = vertx.setTimer(interval, this);
                    }
                });
            }
        }
    };
    periodic.handle(null);
}
```

reconcileAllTopics()

```java
Future<?> reconcileAllTopics(String reconciliationType) {
    LOGGER.infoOp("Starting {} reconciliation", reconciliationType);
    return kafka.listTopics().recover(ex -> Future.failedFuture(
            new OperatorException("Error listing existing topics during " + reconciliationType + " reconciliation", ex)
    )).compose(topicNamesFromKafka ->
            // 调和在kafka实例中发现的topic
            reconcileFromKafka(reconciliationType, topicNamesFromKafka.stream().map(TopicName::new).collect(Collectors.toList()))
    ).compose(reconcileState -> {
        Future<List<KafkaTopic>> ktFut = k8s.listResources();
        return ktFut.recover(ex -> Future.failedFuture(
                new OperatorException("Error listing existing KafkaTopics during " + reconciliationType + " reconciliation", ex)
        )).map(ktList -> {
            reconcileState.setKafkaTopics(ktList);
            return reconcileState;
        });
    }).compose(reconcileState -> {
        List<Future> futs = new ArrayList<>();
        pausedTopicCounter.set(0);
        topicCounter.set(reconcileState.ktList.size());
        for (KafkaTopic kt : reconcileState.ktList) {
            if (Annotations.isReconciliationPausedWithAnnotation(kt)) {
                pausedTopicCounter.getAndIncrement();
            }
            LogContext logContext = LogContext.periodic(reconciliationType + "kube " + kt.getMetadata().getName(), kt.getMetadata().getNamespace(), kt.getMetadata().getName()).withKubeTopic(kt);
            Topic topic = TopicSerialization.fromTopicResource(kt);
            TopicName topicName = topic.getTopicName();
            if (reconcileState.failed.containsKey(topicName)) {
                LOGGER.traceCr(logContext.toReconciliation(), "Already failed to reconcile {}", topicName);
                reconciliationsCounter.increment();
                failedReconciliationsCounter.increment();
            } else if (reconcileState.succeeded.contains(topicName)) {
                LOGGER.traceCr(logContext.toReconciliation(), "Already successfully reconciled {}", topicName);
                reconciliationsCounter.increment();
                successfulReconciliationsCounter.increment();
            } else if (reconcileState.undetermined.contains(topicName)) { 
                futs.add(reconcileWithKubeTopic(logContext, kt, reconciliationType, new ResourceName(kt), topic.getTopicName()).compose(r -> {
                   
                    reconcileState.undetermined.remove(topicName);
                    reconcileState.succeeded.add(topicName);
                    return Future.succeededFuture(Boolean.TRUE);
                }));
            } else {
                // 调和存在与k8s集群的topic
                LOGGER.debugCr(logContext.toReconciliation(), "Topic {} exists in Kubernetes, but not Kafka", topicName, logTopic(kt));
                futs.add(reconcileWithKubeTopic(logContext, kt, reconciliationType, new ResourceName(kt), topic.getTopicName()).compose(r -> {
                  
                    reconcileState.succeeded.add(topicName);
                    return Future.succeededFuture(Boolean.TRUE);
                }));
            }
        }
        return CompositeFuture.join(futs).compose(joined -> {
            List<Future> futs2 = new ArrayList<>();
            for (Throwable exception : reconcileState.failed.values()) {
                futs2.add(Future.failedFuture(exception));
            }
            
            for (TopicName tn : reconcileState.undetermined) {
                LogContext logContext = LogContext.periodic(reconciliationType + "-" + tn, namespace, tn.asKubeName().toString());
                futs2.add(executeWithTopicLockHeld(logContext, tn, new Reconciliation(logContext, "delete-remaining", true) {
                    @Override
                    public Future<Void> execute() {
                        observedTopicFuture(null);
                        return getKafkaAndReconcile(this, logContext, tn, null, null);
                    }
                }));
            }
            return CompositeFuture.join(futs2);
        });
    });
}
```

这边方法太多了，最后主要进入的方法就是reconcile()这个方法

```java
/**
     * 0. 为我们设置一些持久的ZK节点
     * 1.当更新KafkaTopic时，我们也会更新我们的ZK节点
     * 2. 当更新Kafka时，我们也会更新我们的ZK节点
     * 3.当调和时，我们得到所有三个版本的Topic、k8s、kafka和privateState
     * - 如果privateState不存在。
     * - 如果k8s不存在，我们推断它已经在kafka中被创建，我们从kafka中创建它的k8s
     * - 如果kafka不存在，我们推断它是在k8s中创建的，并且我们从k8s中创建它。
     * - 如果两者都存在，并且是相同的：这很好
     * - 如果两者都存在，而且不同。我们使用最新的mtime的那个。
     * - 在上述所有情况下，我们创建privateState
     * - 如果privateState确实存在。
     * - 如果k8s不存在，我们推断它被删除了，并删除kafka
     * - 如果kafka不存在，我们的理由是它被删除了，并且我们删除k8s
     * - 如果两者都不存在，我们就删除privateState。
     * - 如果两者都存在，那么三者都存在，我们需要进行协调。
     * - 我们计算privateState->k8s和privateState->kafka的差异，并将两者合并。
     * - 如果有冲突 => 错误
     * - 否则我们将合并后的差异应用于privateState，并将其用于k8s和kafka。
     * - 在上述所有情况下，我们更新privateState
     * 主题识别应该是由uid/cxid组成，而不是由名字组成。
     * Topic identification should be by uid/cxid, not by name.
     */
Future<Void> reconcile(Reconciliation reconciliation, final LogContext logContext, final HasMetadata involvedObject,
               final Topic k8sTopic, final Topic kafkaTopic, final Topic privateTopic) {
    final Future<Void> reconciliationResultHandler;
    {
        TopicName topicName = k8sTopic != null ? k8sTopic.getTopicName() : kafkaTopic != null ? kafkaTopic.getTopicName() : privateTopic != null ? privateTopic.getTopicName() : null;
        LOGGER.infoCr(logContext.toReconciliation(), "Reconciling topic {}, k8sTopic:{}, kafkaTopic:{}, privateTopic:{}", topicName, k8sTopic == null ? "null" : "nonnull", kafkaTopic == null ? "null" : "nonnull", privateTopic == null ? "null" : "nonnull");
    }
    if (k8sTopic != null && Annotations.isReconciliationPausedWithAnnotation(k8sTopic.getMetadata())) {
        LOGGER.debugCr(logContext.toReconciliation(), "Reconciliation paused, not applying changes.");
        reconciliationResultHandler = Future.succeededFuture();
    } else if (privateTopic == null) {
        if (k8sTopic == null) {
            if (kafkaTopic == null) {
                // All three null: This happens reentrantly when a topic or KafkaTopic is deleted
                LOGGER.debugCr(logContext.toReconciliation(), "All three topics null during reconciliation.");
                reconciliationResultHandler = Future.succeededFuture();
            } else {
                // it's been created in Kafka => create in k8s and privateState
                LOGGER.debugCr(logContext.toReconciliation(), "topic created in kafka, will create KafkaTopic in k8s and topicStore");
                reconciliationResultHandler = createResource(logContext, kafkaTopic)
                        .compose(createdKt -> {
                            reconciliation.observedTopicFuture(createdKt);
                            return createInTopicStore(logContext, kafkaTopic, involvedObject);
                        });
            }
        } else if (kafkaTopic == null) {
            // it's been created in k8s => create in Kafka and privateState
            LOGGER.debugCr(logContext.toReconciliation(), "KafkaTopic created in k8s, will create topic in kafka and topicStore");
            reconciliationResultHandler = createKafkaTopic(logContext, k8sTopic, involvedObject)
                .compose(ignore -> createInTopicStore(logContext, k8sTopic, involvedObject))
                // Kafka will set the message.format.version, so we need to update the KafkaTopic to reflect
                // that to avoid triggering another reconciliation
                .compose(ignored -> getFromKafka(logContext.toReconciliation(), k8sTopic.getTopicName()))
                .compose(kafkaTopic2 -> {
                    LOGGER.debugCr(logContext.toReconciliation(), "Post-create kafka {}", kafkaTopic2);
                    if (kafkaTopic2 == null) {
                        LOGGER.errorCr(logContext.toReconciliation(), "Post-create kafka unexpectedly null");
                        return Future.succeededFuture();
                    }
                    return update3Way(reconciliation, logContext, involvedObject, k8sTopic, kafkaTopic2, k8sTopic);
                });
                //.compose(createdKafkaTopic -> update3Way(logContext, involvedObject, k8sTopic, createdKafkaTopic, k8sTopic));
        } else {
            reconciliationResultHandler = update2Way(reconciliation, logContext, involvedObject, k8sTopic, kafkaTopic);
        }
    } else {
        if (k8sTopic == null) {
            if (kafkaTopic == null) {
                // delete privateState
                LOGGER.debugCr(logContext.toReconciliation(), "KafkaTopic deleted in k8s and topic deleted in kafka => delete from topicStore");
                reconciliationResultHandler = deleteFromTopicStore(logContext, involvedObject, privateTopic.getTopicName());
            } else {
                // it was deleted in k8s so delete in kafka and privateState
                // If delete.topic.enable=false then the resulting exception will be ignored and only the privateState topic will be deleted
                LOGGER.debugCr(logContext.toReconciliation(), "KafkaTopic deleted in k8s => delete topic from kafka and from topicStore");
                reconciliationResultHandler = deleteKafkaTopic(logContext, kafkaTopic.getTopicName()).recover(thrown -> handleTopicDeletionDisabled(thrown, logContext))
                    .compose(ignored -> deleteFromTopicStore(logContext, involvedObject, privateTopic.getTopicName()));
            }
        } else if (kafkaTopic == null) {
            // it was deleted in kafka so delete in k8s and privateState
            LOGGER.debugCr(logContext.toReconciliation(), "topic deleted in kafkas => delete KafkaTopic from k8s and from topicStore");
            reconciliationResultHandler = deleteResource(logContext, privateTopic.getOrAsKubeName())
                    .compose(ignore -> {
                        reconciliation.observedTopicFuture(null);
                        return deleteFromTopicStore(logContext, involvedObject, privateTopic.getTopicName());
                    });
        } else {
            // all three exist
            LOGGER.debugCr(logContext.toReconciliation(), "3 way diff");
            reconciliationResultHandler = update3Way(reconciliation, logContext, involvedObject,
                    k8sTopic, kafkaTopic, privateTopic);
        }
    }

    return reconciliationResultHandler.onComplete(res -> {
        if (res.succeeded()) {
            reconciliation.succeeded();
        } else {
            reconciliation.failed();
        }
    });
}
```

