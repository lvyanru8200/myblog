---
title: "Kafka Op02"
subtitle: ""
date: 2022-07-27T20:05:19+08:00
lastmod: 2022-07-27T20:05:19+08:00
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

#### Kafka Operator代码阅读02--kafka CRD逻辑

#### 本文主旨：

- [strimize-kafka-opertaor](https://github.com/strimzi/strimzi-kafka-operator) User CRD 代码阅读

#### User Operator

​    根据01中的说明，user Operator是通过kafka Operator中调和逻辑的reconcileEntityOperator创建的，这里首先看看EntityOperator是如何创建的

reconcileEntityOperator()方法依然是首先构建entityOperatorReconciler，然后调用他的reconcile方法

```java
Future<ReconciliationState> reconcileEntityOperator(Supplier<Date> dateSupplier)    {
    return entityOperatorReconciler()
            .reconcile(pfa.isOpenshift(), imagePullPolicy, imagePullSecrets, dateSupplier)
            .map(this);
}
```

entityOperatorReconciler().reconcile()

```java
public Future<Void> reconcile(boolean isOpenShift, ImagePullPolicy imagePullPolicy, List<LocalObjectReference> imagePullSecrets, Supplier<Date> dateSupplier)    {
    return serviceAccount()
            // 创建entityOperator使用的role
            .compose(i -> entityOperatorRole())
            // 创建topic Operator使用的role
            .compose(i -> topicOperatorRole())
            // 创建user Operator使用的role
            .compose(i -> userOperatorRole())
            // 创建topic以及user的rolebinding
            .compose(i -> topicOperatorRoleBindings())
            .compose(i -> userOperatorRoleBindings())
            // 创建topic以及user的configmap
            .compose(i -> topicOperagorConfigMap())
            .compose(i -> userOperatorConfigMap())
            // 删除旧的entityOperator的secret，如果有的话
            .compose(i -> deleteOldEntityOperatorSecret())
            // 构建新的topic以及user的secret
            .compose(i -> topicOperatorSecret(dateSupplier))
            .compose(i -> userOperatorSecret(dateSupplier))
            // 创建deploy
            .compose(i -> deployment(isOpenShift, imagePullPolicy, imagePullSecrets))
            // 健康检查
            .compose(i -> waitForDeploymentReadiness());
}
```

进入调和的方式与kafka operator一样createOrUpdate方法

```java
protected Future<KafkaUserStatus> createOrUpdate(Reconciliation reconciliation, KafkaUser resource) {
    KafkaUserModel user;
    KafkaUserStatus userStatus = new KafkaUserStatus();

    try {
        user = KafkaUserModel.fromCrd(resource, config.getSecretPrefix(), config.isAclsAdminApiSupported(), config.isKraftEnabled());
        LOGGER.debugCr(reconciliation, "Updating User {} in namespace {}", reconciliation.name(), reconciliation.namespace());
    } catch (Exception e) {
        LOGGER.warnCr(reconciliation, e);
        StatusUtils.setStatusConditionAndObservedGeneration(resource, userStatus, Future.failedFuture(e));
        return Future.failedFuture(new ReconciliationException(userStatus, e));
    }

    Promise<KafkaUserStatus> handler = Promise.promise();
		// 这里为部署userOperator创建与kafka通信的casecret
    secretOperations.getAsync(reconciliation.namespace(), user.getSecretName())
            .compose(userSecret -> maybeGenerateCredentials(reconciliation, user, userSecret))
            .compose(ignore -> reconcileCredentialsQuotasAndAcls(reconciliation, user, userStatus))
            .onComplete(reconciliationResult -> {
                StatusUtils.setStatusConditionAndObservedGeneration(resource, userStatus, reconciliationResult.mapEmpty());
                userStatus.setUsername(user.getUserName());

                if (reconciliationResult.succeeded())   {
                    handler.complete(userStatus);
                } else {
                    handler.fail(new ReconciliationException(userStatus, reconciliationResult.cause()));
                }
            });

    return handler.future();
}
```

看下useroperator的main函数

```java
public static void main(String[] args) {
    LOGGER.info("UserOperator {} is starting", Main.class.getPackage().getImplementationVersion());
    // 根据env构建configmap
    UserOperatorConfig config = UserOperatorConfig.fromMap(System.getenv());
    // 创建metrics
    VertxOptions options = new VertxOptions().setMetricsOptions(
            new MicrometerMetricsOptions()
                    .setPrometheusOptions(new VertxPrometheusOptions().setEnabled(true))
                    .setJvmMetricsEnabled(true)
                    .setEnabled(true));
    Vertx vertx = Vertx.vertx(options);

    KubernetesClient client = new DefaultKubernetesClient();
    AdminClientProvider adminClientProvider = new DefaultAdminClientProvider();
	
    run(vertx, client, adminClientProvider, config).onComplete(ar -> {
        if (ar.failed()) {
            LOGGER.error("Unable to start operator", ar.cause());
            System.exit(1);
        }
    });
}
```

看下run方法

```java
static Future<String> run(Vertx vertx, KubernetesClient client, AdminClientProvider adminClientProvider, UserOperatorConfig config) {
    Util.printEnvInfo();
    String dnsCacheTtl = System.getenv("STRIMZI_DNS_CACHE_TTL") == null ? "30" : System.getenv("STRIMZI_DNS_CACHE_TTL");
    Security.setProperty("networkaddress.cache.ttl", dnsCacheTtl);

    OpenSslCertManager certManager = new OpenSslCertManager();
    SecretOperator secretOperations = new SecretOperator(vertx, client);
    CrdOperator<KubernetesClient, KafkaUser, KafkaUserList> crdOperations = new CrdOperator<>(vertx, client, KafkaUser.class, KafkaUserList.class, KafkaUser.RESOURCE_KIND);
    return createAdminClient(adminClientProvider, config, secretOperations)
            .compose(adminClient -> {
                 // 构建simpleacloperator，这些都是useroperator的认证方式
                SimpleAclOperator aclOperations = new SimpleAclOperator(vertx, adminClient);
                // ca operator
                ScramCredentialsOperator scramCredentialsOperator = new ScramCredentialsOperator(vertx, adminClient);
                // quota operator
                QuotasOperator quotasOperator = new QuotasOperator(vertx, adminClient);
								// kafkauser operator创建
                KafkaUserOperator kafkaUserOperations = new KafkaUserOperator(vertx, certManager, crdOperations,
                        secretOperations, scramCredentialsOperator, quotasOperator, aclOperations, config);

                Promise<String> promise = Promise.promise();
                UserOperator operator = new UserOperator(config.getNamespace(),
                        config,
                        client,
                        kafkaUserOperations);
                vertx.deployVerticle(operator,
                    res -> {
                        if (res.succeeded()) {
                            LOGGER.info("User Operator verticle started in namespace {}", config.getNamespace());
                        } else {
                            LOGGER.error("User Operator verticle in namespace {} failed to start", config.getNamespace(), res.cause());
                            System.exit(1);
                        }
                        promise.handle(res);
                    });
                return promise.future();
            });
}
```

启动后依然是通过eventReceived监听事件,调用reconcileAll或reconcile方法，最后调用kafkaUser的createOrUpdate方法

```java
protected Future<KafkaUserStatus> createOrUpdate(Reconciliation reconciliation, KafkaUser resource) {
    KafkaUserModel user;
    KafkaUserStatus userStatus = new KafkaUserStatus();

    try {
        user = KafkaUserModel.fromCrd(resource, config.getSecretPrefix(), config.isAclsAdminApiSupported(), config.isKraftEnabled());
        LOGGER.debugCr(reconciliation, "Updating User {} in namespace {}", reconciliation.name(), reconciliation.namespace());
    } catch (Exception e) {
        LOGGER.warnCr(reconciliation, e);
        StatusUtils.setStatusConditionAndObservedGeneration(resource, userStatus, Future.failedFuture(e));
        return Future.failedFuture(new ReconciliationException(userStatus, e));
    }

    Promise<KafkaUserStatus> handler = Promise.promise();
    // secret operator用来配置kafka user所配置的用户密钥等信息
    secretOperations.getAsync(reconciliation.namespace(), user.getSecretName())
            // maybeGenerateCredentials根据KafkaUser的配置和用户secret，设置或生成给定用户的凭证
            .compose(userSecret -> maybeGenerateCredentials(reconciliation, user, userSecret))
            // 调和kafkauser所配置的credentials, quotas 和acl
            .compose(ignore -> reconcileCredentialsQuotasAndAcls(reconciliation, user, userStatus))
            .onComplete(reconciliationResult -> {
                StatusUtils.setStatusConditionAndObservedGeneration(resource, userStatus, reconciliationResult.mapEmpty());
                userStatus.setUsername(user.getUserName());

                if (reconciliationResult.succeeded())   {
                    handler.complete(userStatus);
                } else {
                    handler.fail(new ReconciliationException(userStatus, reconciliationResult.cause()));
                }
            });

    return handler.future();
}
```

看下maybeGenerateCredentials()

```java
private Future<Void> maybeGenerateCredentials(Reconciliation reconciliation, KafkaUserModel user, Secret userSecret)   {
    // 根据kafka user的authentication字段判断是scram类型还是tls类型，根据不同类型的认证方式生成secret
    if (user.isScramUser()) {
        return maybeGenerateScramCredentials(reconciliation, user, userSecret);
    } else if (user.isTlsUser())    {
        return maybeGenerateTlsCredentials(reconciliation, user, userSecret);
    } else {
        return Future.succeededFuture();
    }
}
```

reconcileCredentialsQuotasAndAcls()

```java
private CompositeFuture reconcileCredentialsQuotasAndAcls(Reconciliation reconciliation, KafkaUserModel user, KafkaUserStatus userStatus)   {
    // 构建tls或者scram quota
    Set<SimpleAclRule> tlsAcls = null;
    Set<SimpleAclRule> scramOrNoneAcls = null;
    KafkaUserQuotas tlsQuotas = null;
    KafkaUserQuotas scramOrNoneQuotas = null;
	
    if (user.isTlsUser() || user.isTlsExternalUser())   {
        tlsAcls = user.getSimpleAclRules();
        tlsQuotas = user.getQuotas();
    } else if (user.isScramUser() || user.isNoneUser())  {
        scramOrNoneAcls = user.getSimpleAclRules();
        scramOrNoneQuotas = user.getQuotas();
    }

    // 调和用户SCRAM-SHA-512认证方式
    Future<ReconcileResult<String>> scramCredentialsFuture;
    if (config.isKraftEnabled()) {
        // kRaft不支持SCRAM-SHA认证方式，这里需要判断下
        scramCredentialsFuture = Future.succeededFuture(ReconcileResult.noop(null));
    } else {
        scramCredentialsFuture = scramCredentialsOperator.reconcile(reconciliation, user.getName(), user.getScramSha512Password());
    }

    // tlsquota以及quota不同的调和方法
    Future<ReconcileResult<KafkaUserQuotas>> tlsQuotasFuture = quotasOperator.reconcile(reconciliation, KafkaUserModel.getTlsUserName(reconciliation.name()), tlsQuotas);
    Future<ReconcileResult<KafkaUserQuotas>> quotasFuture = quotasOperator.reconcile(reconciliation, KafkaUserModel.getScramUserName(reconciliation.name()), scramOrNoneQuotas);

    // 将user 产生的用户secret与认证进行核对
    Future<ReconcileResult<Secret>> userSecretFuture = reconcileUserSecret(reconciliation, user, userStatus);

    // ACL需要为普通和TLS用户进行协调。它将（可能）为一个用户设置，为另一个用户删除
    Future<ReconcileResult<Set<SimpleAclRule>>> aclsTlsUserFuture;
    Future<ReconcileResult<Set<SimpleAclRule>>> aclsScramUserFuture;

    if (config.isAclsAdminApiSupported()) {
        aclsTlsUserFuture = aclOperations.reconcile(reconciliation, KafkaUserModel.getTlsUserName(reconciliation.name()), tlsAcls);
        aclsScramUserFuture = aclOperations.reconcile(reconciliation, KafkaUserModel.getScramUserName(reconciliation.name()), scramOrNoneAcls);
    } else {
        aclsTlsUserFuture = Future.succeededFuture(ReconcileResult.noop(null));
        aclsScramUserFuture = Future.succeededFuture(ReconcileResult.noop(null));
    }

    return CompositeFuture.join(scramCredentialsFuture, tlsQuotasFuture, quotasFuture, aclsTlsUserFuture, aclsScramUserFuture, userSecretFuture);
}
```

总体来说，useroperator根据你所配置的认证方式以及acl配置还有quota配置进行设置
