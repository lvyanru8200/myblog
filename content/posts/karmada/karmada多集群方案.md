---
title: "Karmada多集群方案"
subtitle: ""
date: 2022-10-03T14:49:44+08:00
lastmod: 2022-10-03T14:49:44+08:00
draft: true
author: "整挺好"
authorLink: ""
description: ""
license: "整挺好许可"
images: []

tags: []
categories: []

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

# 方案一：多集群VIP+多NodePort

### 方案目的：

在多k8s集群上使用Operator的方式对Mongo进行生命周期管理。

### 方案依赖：

- Karmada（多集群底座）
- 每个集群对应的Vip（Mongo东西向流量依赖）
- Operator（Mongo生命周期管理）

### 方案概要：

现有ClusterA，ClusterB，ClusterC，ClusterD四个集群，ClusterA作为控制面，Cluster B/C/D 作为数据面，同时BCD集群分别具有VIPB，VIPC，VIPD这三个VIP，Operator分为控制面Operator以及数据面Operator，控制面Operator作为入口负责下发Mongo Cr，控制面使用ServiceTp作为crud对象，经由控制面Operator处理出Mongo Cr下发至各数据面，数据面Operator监控到下发的Mongo Cr，负责真正的调和，以及服务的生命周期管理。东西向采用Vip加各Mongo服务NodePort方式进行通信，南北向使用VIPB/C/D加任意Mongo服务的NodePort方式进行通信。同时，对于每个Mongo Cr来说，控制面Operator同时还要兼顾他在多集群之间K8s编排资源落地的抉择。

### 方案架构图：

<div align=center>
<img src="/images/20.png" />
</div>

### 方案详解：

+ 开发说明

| 使用工具           | 目的                | 版本     |
| -------------- | ----------------- | ------ |
| Karmada        | Karmada多集群Cr的分发能力 | 1.3.0  |
| Golang         | 开发语言              | 1.19.1 |
| Kubebuilder    | Operator脚手架       | v3.6.0 |
| Kubernetes/DCE | 数据中心              | ???    |
| MongoDB        | Mongo服务           | 6.0.1  |

+ CRD设计
   + ServiceTp(控制面Operator需要处理的CR)

| group                       | service         |                     |
| --------------------------- | --------------- | ------------------- |
| kind                        | ServiceTp       |                     |
| domain                      | daocloud.io     |                     |
| version                     | v1alpha         |                     |
| name                        | 服务名称            | sample-serviceTp    |
| namespace                   | 服务所在命名空间        | sample-ns           |
| labels                      | 服务标签            |                     |
| spec.replicas               | 服务副本数           | 3                   |
| spec.config                 | 服务配置            | [string]interfact{} |
| spec.scheduler              | 服务调度模式设置        | dynamic<br>static   |
| spec.enableExport           | 是否启用服务监控        | true                |
| spec.image.registry         | 服务镜像仓库服务地址      | daocloud.io         |
| spec.image.repository       | 服务镜像仓库          | atsctoo             |
| spec.image.imagePullPolicay | 服务镜像拉取方式        |                     |
| spec.image.imagePullSecret  | 配置拉取镜像使用的secret |                     |
| spec.configRef              | 配置文件引用          | sample-configmap    |
| spec.limits.cpu             | 服务cpu限制         | 5c                  |
| spec.limits.memory          | 服务memory限制      | 5Gi                 |
| spec.limits.storage         | 服务storage限制     | 3G                  |
| spec.requests.cpu           | 服务cpu请求         | 5c                  |
| spec.requests.memory        | 服务memory请求      | 5Gi                 |
| spec.requests.storage       | 服务storage限制     | 3G                  |
| spec.storageclass           | 服务使用的存储类        |                     |
| status.result               | 服务下发的结果         |                     |
| status.stats                | 是否成功            | Success/Failed...   |
| status.accessAddr           | 服务访问地址          |                     |
| spec.cluster                |                 |                     |
|                             |                 |                     |

+ MongoDB(数据面Operator需要处理的CR)

| group                 | mongo              |
| --------------------- | ------------------ |
| kind                  | MongoDB            |
| domain                | daocloud.io        |
| version               | v1alpha            |
| name                  | mongo服务名称          |
| namespace             | mongo服务所在命名空间      |
| annotations           | serviceTpName:服务名称 |
| labels                | serviceTp.labels   |
| spec.image            | mongo镜像            |
| spec.imagePullPolicy  | mongo镜像拉取策略        |
| spec.requests.cpu     | mongo服务请求的cpu      |
| spec.requests.memory  | mongo服务请求的memory   |
| spec.requests.storage | mongo服务请求的storage  |
| spec.limits.cpu       |                    |
| spec.limits.memory    |                    |
| spec.limits.storage   |                    |
| spec.replicas         | mongo服务副本数         |

+ 控制面Operator，自己调度
   - 控制面Operator Reconcile过程：

     <div align=center>
        <img src="/images/21.png" />
     </div>

      - 控制面Operator Reconcile过程叙述：

控制面Operator负责serviceTp CR的调和，serviceTp对象定义了服务的基本信息，副本数，资源配置等，控制面Operator对serviceTp的调和过程为首先会根据serviceTp配置在控制面创建服务所需要的ConfigMap/Secret/Service以及MongoDB CR，创建完成后，随后创建PropagationPolicy对象，Karmada会对该对象进行处理，并通过Karmada Scheduler以及控制面拓展Scheduler创建并填充ResourceBinding对象，控制面Operator会Watch ResourceBinding资源，当发现ResourceBinding Spec.Cluster字段被填充的时候，即具有调度结果的时候，创建对应集群副本数目的service并通过pp下发，并且还会创建一个ConfigMap，该ConfigMap中存放了Mongo实例在各个集群中构建副本集应该遵循的配置，随后创建pp将该ConfigMap下发至需要调度Mongo服务的集群上，随后创建根据创建的crd状态获取hook去聚合各个成员集群mongodb的status，聚合至serviceTp，完成一次调和。

+ 数据面Operator
   - 数据面Operator Reconcile过程：

     <div align=center>
        <img src="/images/22.png" />
     </div>

      - 数据面Operator Reconcile过程叙述：

数据面Operator负责MongoDB CR的调和，MongoDB对象定义了Mongo服务的详细信息，当控制面下发MongoDB CR至数据面之后，数据面Operator会Watch由控制面下发的service/configmap/secret对象，当这些对象创建成功后，数据面Operator开始Mongo服务k8s资源对象的创建，创建完成后，根据配置以及hostConf中mongo应该遵循的配置开始构建mongo副本集模式，副本集模式构建完成后，数据面Operator进行一些检查逻辑，同时进行InterpretStatus操作聚合状态至控制面，完成一次调和。

+ 更新以及故障恢复
   - 更新过程：
      - 扩容：
         - 控制面：更新serviceTp副本数，例如原本serviceTp副本数是5，现在更新至7，进入调和之后，判断serviceTp副本数与MongoDB副本数是否一致，不一致进入控制面createResource阶段，所进行的操作为更新当前控制面上的MongoDB实例副本由5→ 7，随后依旧是pp的创建的，以及ResourceBinding调度结果的获取，这里调度属于karmada中的扩缩容调度+/-自定义调度逻辑，则调度结果可能为clusterA上Mongo副本由2 → 3，clusterB上Mongo副本由1 → 2，则创建新的service继续分发至clusterA于clusterB，对于hostconf则会做更新控制面hostconf操作。
         - 数据面：Watch到service的创建/hostconf中配置数量的变更操作后进行正常的更新MongoDB副本操作
         - 缩容：
            - 控制面：更新serviceTp副本数，判断serviceTp副本数与MongoDB副本数是否一致，不一致直接更新MongoDB副本数，调度结果出来后，走正常逻辑，如果一致，则检查service数量是否一致，不一致则删掉多余的service。
            - 数据面：MongoDB副本数有更新，如果primary在当前节点，则下线secondary节点，如果primary不在当前cluster，直接按需缩容。
         - 配置更新：
            - 控制面：更新configmap正常逻辑
            - 数据面：挂载的configmap更新有延迟，延迟过后刷新一遍configmap
      - 故障恢复：
         - pod挂掉后启动：不影响。
         - pod挂掉后不启动：该cluster问题，该cluster的MongoDB服务出问题控制面重新调和不影响。
         - service被误删除：控制面会下发，不影响。
         - vip失效：不影响使用。
         - 集群失联：不影响使用。
   + 中间件调度算法
      + 中间件调度算法主要分为以下三个方面
         1. 基于资源的调度
            - estimator
            - ...
         2. 基于高可用的调度
            - mongo服务主从角色在各cluster上
            - ...
         3. 基于性能的调度
            - 对于中间件服务自身性能(读/写/复制)具有影响的因素(磁盘io,ssd)
            - ...
      + 基于123的调度整合

     <div align=center>
        <img src="/images/23.png" />
     </div>
     
         + 中间件调度算法逻辑叙述

         中间件调度(middleware scheduler)以sdk的方式在每次MultiClusterServer调和中介入，middleware scheduler以MultiClusterServer中配置的replicaset以及resource.limits为参数，对于首次调度的multiclusterserver实例，首先会通过karmada-estimator组件得到一个可以完全部署起来服务的调度结果，而本次调度结果可以分为以下二种情况：

1. 调度结果中每个cluster的最大副本数都不小于1即>=1
2. 调度结果中最大副本数不小于1的cluster不足所有cluster的一半

对于情况1:  可以部署符合1，2特性。

对于情况2: 不能部署，2特性无法保证，多数集群断电则无法保证服务，而这种情况的出现多数是由于集群资源问题导致。

如果没有基于性能调度的过程，则完成首次调度，为当前实例添加first-middleware-schduler：success注解，对于具有首次调度成功的实例，每次该实例status的变化都会再次进入调度队列，重新执行资源调度与高可用调度，如果结果与第一次一致，则不进行真正的调度，如果不一样，则进行重新调度，但要保证情况1或者情况2。

- 情况2说明(硬性规定)：

对于情况2出现的可能：

- 本身5个cluster，但是3个cluster资源不足以部署1个副本，切换resources.requests再次进入调度，如果结果依然是情况2，则pending
- 本身5个cluster，且首次调度成功，但在下发/后面未知情况，导致实际部署情况不满足大多数条件，重新进入调度队列。
         - 软规定：
            - 如果出现情况2，不满足大多数依然可以部署

