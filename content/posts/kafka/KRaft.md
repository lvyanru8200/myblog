---
title: "KRaft"
subtitle: ""
date: 2022-08-01T09:44:18+08:00
lastmod: 2022-08-01T09:44:18+08:00
draft: true
author: "整挺好"
authorLink: ""
description: ""
license: "整挺好许可"
images: []

tags: ["Kafka"]
categories: ["Kafka"]

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

### Kafka Raft

#### 阅读须知：

- 本文中所指kafka版本为3.2.x版本
- 后续kafka关于KRaft更新本人会吃持续关注并记录下来

#### 背景介绍：

KRaft又名KIP-500，由[KAFKA-9119](https://issues.apache.org/jira/browse/KAFKA-9119)jira单引出，kafka开发人员称之为KRaft mode(Kafka Raft 元数据模式)，由于Kafka 使用 ZooKeeper 来存储关于分区和代理的元数据，并选择一个代理作为 Kafka 控制器。kafka开发人员想要移除kafka对 ZooKeeper 的依赖，旨在能够以更可扩展和更健壮的方式管理元数据，从而支持更多分区。并且简化 Kafka 的部署和配置。

总结为两点：

- 以更可拓展和更健壮的方式管理元数据：

  ​		元数据不应存储在单独的系统中，而应存储在 Kafka 本身中。这将避免控制器状态和 Zookeeper 状态之间的差异相关的所有问题。与其向代理推送通知，代理应该简单地使用事件日志中的元数据事件。这可确保元数据更改始终以相同的顺序到达。broker能够将元数据本地存储在文件中。当它们启动时，它们只需要从控制器读取更改的内容，而不是完整状态。这将使我们能够以更少的 CPU 消耗支持更多的分区。

- 简化kafka的部署和配置：

  ​		ZooKeeper 是一个独立的系统，具有自己的配置文件语法、管理工具和部署模式。这意味着系统管理员需要学习如何管理和部署两个独立的分布式系统才能部署 Kafka。对于管理员来说，这可能是一项艰巨的任务，尤其是在他们对部署 Java 服务不是很熟悉的情况下。统一系统将极大地改善运行 Kafka 的“第一天”体验，并有助于扩大其采用范围。

  ​		因为 Kafka 和 ZooKeeper 配置是分开的，所以很容易出错。例如，管理员可能会在 Kafka 上设置 SASL，并错误地认为他们已经保护了通过网络传输的所有数据。事实上，为了做到这一点，还需要在单独的外部 ZooKeeper 系统中配置安全性。统一这两个系统将提供统一的安全配置模型。

  ​		最后，未来我们可能希望支持单节点 Kafka 模式。这对于想要在不启动多个守护进程的情况下快速测试 Kafka 的人很有用。删除 ZooKeeper 依赖项使这成为可能。

#### 变革：

**先看下Zookeeper模式下的Kafka:**

​		一个 Kafka 集群包含多个代理节点，以及一个外部的 ZooKeeper 节点法定人数。但是这种架构模式下的Kafka集群除了附带Zookeeper成本之外，具有的一个问题还是当外部命令行工具和实用程序可以修改ZooKeeper 中的状态，而无需broker控制器的参与，这些一集群多系统的割裂，使得用户很难知道broker控制器上内存中的状态是否真正反映了 ZooKeeper 中的持久状态。

**看下KRaft模式下的Kafka:**

<div align=center><img src="/images/7.png" />
</div>

​		如右边的图所示，使用三个控制器节点替代了三个 ZooKeeper 节点，我们将右图上半部分三个kafka节点称为控制器节点，下半部分称为broker节点，控制器节点有一个选主的过程，这是保证存放元数据节点的高可用，broker节点从控制器节点拉取元数据的更新，有别于之前控制器节点像broker节点推送更新。

**控制器节点高可用保证:**

​		控制器节点存储当前kafka集群元数据的每一次变化的信息,Raft quorum， 原本存储在ZooKeeper中的所有内容，如主题、分区、ISR、配置等，都将存储在控制器节点的metadata log中。

​		使用Raft算法，控制器节点将从它们之间选出一个领导者，而不依赖任何外部系统。 元数据日志的领导者被称为master控制器。 master控制器处理所有来自broker节点的RPC请求。 fllower控制器复制写入master控制器的数据，并在master控制器发生故障时充当热备用。 因为控制器现在都会跟踪最新的状态，所以控制器的故障切换不需要一个漫长的重载期，就可以把所有的状态转移到新的控制器，就像ZooKeeper一样，Raft需要大多数节点都在运行，才能继续运行。 因此，一个三节点的控制器集群可以承受一次故障。 五个节点的控制器集群可以承受两次故障，以此类推，定期地，控制器会将元数据的快照写到磁盘上。 虽然这在概念上与压缩相似，但代码路径会有些不同，因为我们可以简单地从内存中读取状态，而不是从磁盘中重新读取日志。

**控制器节点获取broker节点元数据：**

​		broker节点通过**MetadataFetch API**从master控制器节点中获取更新，而不是由控制器节点向其他broker推送更新，MetadataFetch类似于fetch请求。 就像获取请求一样，broker将跟踪它获取的最后一次更新的偏移量，并且只从master控制器节点请求较新的更新，broker将把它获取的元数据持久化到磁盘上。 这将使broker能够非常迅速地启动，即使有几十万甚至几百万个分区。 (注意，由于这种持久性是一种优化，我们可以不把它放在第一个版本中，如果它使开发更容易的话)。大多数时候，broker节点应该只需要获取deltas，而不是完整的状态。 然而，如果broker落后于master控制器太多，或者broker根本没有缓存的元数据，控制器将发送一个完整的matedate image，而不是一系列的deltas。

<div align=center><img src="/images/8.png" />
</div>

broker定期的从master控制器中请求元数据更新。 这个请求将作为一个心跳，让控制器知道broker是存活的。

**Broker节点的状态：**

<div align=center><img src="/images/9.png" />
</div>

- Offline: broker进程处于离线状态，要么根本没有运行，要么正在执行启动所需的单节点任务，如初始化JVM或执行日志恢复。
- Fenced: broker处于Fenced状态时，它将不响应来自客户端的RPC。 在启动和尝试获取最新的元数据时，broker将处于fenced状态。 如果它不能连接master控制器，它将重新进入fenced状态。 fenced状态的brokers应该从发送到客户端的元数据中省略。
- Online: 准备好响应客户端的请求。
- Stopping: 当broker收到SIGINT时进入停止状态。 这表明系统管理员要关闭brokers,当一个broker在停止的时候，如果它仍在运行，会先将分区leader从这个broker迁移出去，如果ok，在最后，master控制器会通过在MetadataFetchResponse中返回一个特殊的结果代码，要求broker最终下线。 另外，如果在预先确定的时间内不能移动predetermined，broker将关闭。

**后续更新:**

- [KIP-455：为副本重新分配创建管理 API](https://cwiki.apache.org/confluence/display/KAFKA/KIP-455%3A+Create+an+Administrative+API+for+Replica+Reassignment)
- [KIP-497：添加代理间 API 以更改 ISR](https://cwiki.apache.org/confluence/display/KAFKA/KIP-497%3A+Add+inter-broker+API+to+alter+ISR)
- [KIP-543：扩展 ConfigCommand 的非 ZK 功能](https://cwiki.apache.org/confluence/display/KAFKA/KIP-543%3A+Expand+ConfigCommand's+non-ZK+functionality)
- [KIP-555：在 Kafka 管理工具中弃用直接 Zookeeper 访问](https://cwiki.apache.org/confluence/display/KAFKA/KIP-555%3A+Deprecate+Direct+Zookeeper+access+in+Kafka+Administrative+Tools)
- [KIP-589 添加 API 以更新控制器中的副本状态](https://cwiki.apache.org/confluence/display/KAFKA/KIP-589+Add+API+to+update+Replica+state+in+Controller)
- [KIP-590：将 Zookeeper 突变协议重定向到控制器](https://cwiki.apache.org/confluence/display/KAFKA/KIP-590%3A+Redirect+Zookeeper+Mutation+Protocols+to+The+Controller)
- [KIP-595：元数据仲裁的 Raft 协议](https://cwiki.apache.org/confluence/display/KAFKA/KIP-595%3A+A+Raft+Protocol+for+the+Metadata+Quorum)
- [KIP-631：基于 Quorum 的 Kafka 控制器](https://cwiki.apache.org/confluence/display/KAFKA/KIP-631%3A+The+Quorum-based+Kafka+Controller)

**KRaft参考：**

- Raft 共识算法：Ongaro, D., Ousterhout, J. [寻找可理解的共识算法](https://raft.github.io/raft.pdf)
- 通过预写日志处理元数据: 
  - Shvachko, K., Kuang, H., Radia, S. Chansler, R. [Hadoop 分布式文件系统](https://cwiki.apache.org/confluence/pages.cs.wisc.edu/~akella/CS838/F15/838-CloudPapers/hdfs.pdf)
  - Balakrishnan, M.、Malkhi, D.、Wobber, T. [Tango：共享日志上的分布式数据结构](http://www.cs.cornell.edu/~taozou/sosp13/tangososp.pdf)

**！！！注意：**

截止目前kafka 3.2版本KRaft仍不是生产就需

**Kafka社区后续后续计划：**

在 Kafka 2.8 中，KRaft 模式在早期访问中发布。通过 Kafka 3.0，它处于预览状态。

 [KIP-833](https://cwiki.apache.org/confluence/display/KAFKA/KIP-833%3A+Mark+KRaft+as+Production+Ready)建议：

- 在即将发布的 Kafka 3.3 版本中，将 KRaft 标记为新集群的生产就绪。
- 在即将发布的 Kafka 3.4 版本中弃用 ZooKeeper 模式
- 计划在 Kafka 4.0 中完全移除 ZooKeeper 模式。

#### 尝鲜：

1. 第一步是使用 kafka-storage 工具为您的新集群生成一个 ID：

   ```shell
   $ ./bin/kafka-storage.sh random-uuid
   xtzWWN4bTjitpL3kfd9s5g
   ```

2.  下一步是格式化存储目录。如果您在单节点模式下运行，您可以使用一个命令来执行此操作：

   ```shell
   $ ./bin/kafka-storage.sh format -t <uuid> -c ./config/kraft/server.properties
   Formatting /tmp/kraft-combined-logs
   ```

​			如果是一个节点话，那么该节点即作为controller又作为broker，更改server.properties配置process.roles=broker,controller

​			如果使用多个节点：应该在每个节点上运行 format 命令。确保为每个集群使用相同的集群 ID，按照如下两个配置文件分别配置broker与controller节点：

- Controller:

  ```properties
  # Licensed to the Apache Software Foundation (ASF) under one or more
  # contributor license agreements.  See the NOTICE file distributed with
  # this work for additional information regarding copyright ownership.
  # The ASF licenses this file to You under the Apache License, Version 2.0
  # (the "License"); you may not use this file except in compliance with
  # the License.  You may obtain a copy of the License at
  #
  #    http://www.apache.org/licenses/LICENSE-2.0
  #
  # Unless required by applicable law or agreed to in writing, software
  # distributed under the License is distributed on an "AS IS" BASIS,
  # WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  # See the License for the specific language governing permissions and
  # limitations under the License.
  
  #
  # This configuration file is intended for use in KRaft mode, where
  # Apache ZooKeeper is not present.  See config/kraft/README.md for details.
  #
  
  ############################# Server Basics #############################
  
  # The role of this server. Setting this puts us in KRaft mode
  process.roles=controller
  
  # The node id associated with this instance's roles
  node.id=1
  
  # The connect string for the controller quorum
  controller.quorum.voters=1@localhost:9093
  
  ############################# Socket Server Settings #############################
  
  # The address the socket server listens on.
  # Note that only the controller listeners are allowed here when `process.roles=controller`, and this listener should be consistent with `controller.quorum.voters` value.
  #   FORMAT:
  #     listeners = listener_name://host_name:port
  #   EXAMPLE:
  #     listeners = PLAINTEXT://your.host.name:9092
  listeners=CONTROLLER://:9093
  
  # A comma-separated list of the names of the listeners used by the controller.
  # This is required if running in KRaft mode.
  controller.listener.names=CONTROLLER
  
  # Maps listener names to security protocols, the default is for them to be the same. See the config documentation for more details
  #listener.security.protocol.map=PLAINTEXT:PLAINTEXT,SSL:SSL,SASL_PLAINTEXT:SASL_PLAINTEXT,SASL_SSL:SASL_SSL
  
  # The number of threads that the server uses for receiving requests from the network and sending responses to the network
  num.network.threads=3
  
  # The number of threads that the server uses for processing requests, which may include disk I/O
  num.io.threads=8
  
  # The send buffer (SO_SNDBUF) used by the socket server
  socket.send.buffer.bytes=102400
  
  # The receive buffer (SO_RCVBUF) used by the socket server
  socket.receive.buffer.bytes=102400
  
  # The maximum size of a request that the socket server will accept (protection against OOM)
  socket.request.max.bytes=104857600
  
  
  ############################# Log Basics #############################
  
  # A comma separated list of directories under which to store log files
  log.dirs=/tmp/kraft-controller-logs
  
  # The default number of log partitions per topic. More partitions allow greater
  # parallelism for consumption, but this will also result in more files across
  # the brokers.
  num.partitions=1
  
  # The number of threads per data directory to be used for log recovery at startup and flushing at shutdown.
  # This value is recommended to be increased for installations with data dirs located in RAID array.
  num.recovery.threads.per.data.dir=1
  
  ############################# Internal Topic Settings  #############################
  # The replication factor for the group metadata internal topics "__consumer_offsets" and "__transaction_state"
  # For anything other than development testing, a value greater than 1 is recommended to ensure availability such as 3.
  offsets.topic.replication.factor=1
  transaction.state.log.replication.factor=1
  transaction.state.log.min.isr=1
  
  ############################# Log Flush Policy #############################
  
  # Messages are immediately written to the filesystem but by default we only fsync() to sync
  # the OS cache lazily. The following configurations control the flush of data to disk.
  # There are a few important trade-offs here:
  #    1. Durability: Unflushed data may be lost if you are not using replication.
  #    2. Latency: Very large flush intervals may lead to latency spikes when the flush does occur as there will be a lot of data to flush.
  #    3. Throughput: The flush is generally the most expensive operation, and a small flush interval may lead to excessive seeks.
  # The settings below allow one to configure the flush policy to flush data after a period of time or
  # every N messages (or both). This can be done globally and overridden on a per-topic basis.
  
  # The number of messages to accept before forcing a flush of data to disk
  #log.flush.interval.messages=10000
  
  # The maximum amount of time a message can sit in a log before we force a flush
  #log.flush.interval.ms=1000
  
  ############################# Log Retention Policy #############################
  
  # The following configurations control the disposal of log segments. The policy can
  # be set to delete segments after a period of time, or after a given size has accumulated.
  # A segment will be deleted whenever *either* of these criteria are met. Deletion always happens
  # from the end of the log.
  
  # The minimum age of a log file to be eligible for deletion due to age
  log.retention.hours=168
  
  # A size-based retention policy for logs. Segments are pruned from the log unless the remaining
  # segments drop below log.retention.bytes. Functions independently of log.retention.hours.
  #log.retention.bytes=1073741824
  
  # The maximum size of a log segment file. When this size is reached a new log segment will be created.
  log.segment.bytes=1073741824
  
  # The interval at which log segments are checked to see if they can be deleted according
  # to the retention policies
  log.retention.check.interval.ms=300000
  ```

- Broker:

  ```properties
  # Licensed to the Apache Software Foundation (ASF) under one or more
  # contributor license agreements.  See the NOTICE file distributed with
  # this work for additional information regarding copyright ownership.
  # The ASF licenses this file to You under the Apache License, Version 2.0
  # (the "License"); you may not use this file except in compliance with
  # the License.  You may obtain a copy of the License at
  #
  #    http://www.apache.org/licenses/LICENSE-2.0
  #
  # Unless required by applicable law or agreed to in writing, software
  # distributed under the License is distributed on an "AS IS" BASIS,
  # WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  # See the License for the specific language governing permissions and
  # limitations under the License.
  
  #
  # This configuration file is intended for use in KRaft mode, where
  # Apache ZooKeeper is not present.  See config/kraft/README.md for details.
  #
  
  ############################# Server Basics #############################
  
  # The role of this server. Setting this puts us in KRaft mode
  process.roles=broker
  
  # The node id associated with this instance's roles
  node.id=2
  
  # The connect string for the controller quorum
  controller.quorum.voters=1@localhost:9093
  
  ############################# Socket Server Settings #############################
  
  # The address the socket server listens on. If not configured, the host name will be equal to the value of
  # java.net.InetAddress.getCanonicalHostName(), with PLAINTEXT listener name, and port 9092.
  #   FORMAT:
  #     listeners = listener_name://host_name:port
  #   EXAMPLE:
  #     listeners = PLAINTEXT://your.host.name:9092
  listeners=PLAINTEXT://localhost:9092
  
  # Name of listener used for communication between brokers.
  inter.broker.listener.name=PLAINTEXT
  
  # Listener name, hostname and port the broker will advertise to clients.
  # If not set, it uses the value for "listeners".
  advertised.listeners=PLAINTEXT://localhost:9092
  
  # A comma-separated list of the names of the listeners used by the controller.
  # This is required if running in KRaft mode. On a node with `process.roles=broker`, only the first listed listener will be used by the broker.
  controller.listener.names=CONTROLLER
  
  # Maps listener names to security protocols, the default is for them to be the same. See the config documentation for more details
  listener.security.protocol.map=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT,SSL:SSL,SASL_PLAINTEXT:SASL_PLAINTEXT,SASL_SSL:SASL_SSL
  
  # The number of threads that the server uses for receiving requests from the network and sending responses to the network
  num.network.threads=3
  
  # The number of threads that the server uses for processing requests, which may include disk I/O
  num.io.threads=8
  
  # The send buffer (SO_SNDBUF) used by the socket server
  socket.send.buffer.bytes=102400
  
  # The receive buffer (SO_RCVBUF) used by the socket server
  socket.receive.buffer.bytes=102400
  
  # The maximum size of a request that the socket server will accept (protection against OOM)
  socket.request.max.bytes=104857600
  
  
  ############################# Log Basics #############################
  
  # A comma separated list of directories under which to store log files
  log.dirs=/tmp/kraft-broker-logs
  
  # The default number of log partitions per topic. More partitions allow greater
  # parallelism for consumption, but this will also result in more files across
  # the brokers.
  num.partitions=1
  
  # The number of threads per data directory to be used for log recovery at startup and flushing at shutdown.
  # This value is recommended to be increased for installations with data dirs located in RAID array.
  num.recovery.threads.per.data.dir=1
  
  ############################# Internal Topic Settings  #############################
  # The replication factor for the group metadata internal topics "__consumer_offsets" and "__transaction_state"
  # For anything other than development testing, a value greater than 1 is recommended to ensure availability such as 3.
  offsets.topic.replication.factor=1
  transaction.state.log.replication.factor=1
  transaction.state.log.min.isr=1
  
  ############################# Log Flush Policy #############################
  
  # Messages are immediately written to the filesystem but by default we only fsync() to sync
  # the OS cache lazily. The following configurations control the flush of data to disk.
  # There are a few important trade-offs here:
  #    1. Durability: Unflushed data may be lost if you are not using replication.
  #    2. Latency: Very large flush intervals may lead to latency spikes when the flush does occur as there will be a lot of data to flush.
  #    3. Throughput: The flush is generally the most expensive operation, and a small flush interval may lead to excessive seeks.
  # The settings below allow one to configure the flush policy to flush data after a period of time or
  # every N messages (or both). This can be done globally and overridden on a per-topic basis.
  
  # The number of messages to accept before forcing a flush of data to disk
  #log.flush.interval.messages=10000
  
  # The maximum amount of time a message can sit in a log before we force a flush
  #log.flush.interval.ms=1000
  
  ############################# Log Retention Policy #############################
  
  # The following configurations control the disposal of log segments. The policy can
  # be set to delete segments after a period of time, or after a given size has accumulated.
  # A segment will be deleted whenever *either* of these criteria are met. Deletion always happens
  # from the end of the log.
  
  # The minimum age of a log file to be eligible for deletion due to age
  log.retention.hours=168
  
  # A size-based retention policy for logs. Segments are pruned from the log unless the remaining
  # segments drop below log.retention.bytes. Functions independently of log.retention.hours.
  #log.retention.bytes=1073741824
  
  # The maximum size of a log segment file. When this size is reached a new log segment will be created.
  log.segment.bytes=1073741824
  
  # The interval at which log segments are checked to see if they can be deleted according
  # to the retention policies
  log.retention.check.interval.ms=300000
  ```

3. 最后，您已准备好在每个节点上启动 Kafka 服务器:

   ```shell
   $ ./bin/kafka-server-start.sh ./config/kraft/server.properties
   [2021-02-26 15:37:11,071] INFO Registered kafka:type=kafka.Log4jController MBean (kafka.utils.Log4jControllerRegistration$)
   [2021-02-26 15:37:11,294] INFO Setting -D jdk.tls.rejectClientInitiatedRenegotiation=true to disable client-initiated TLS renegotiation (org.apache.zookeeper.common.X509Util)
   [2021-02-26 15:37:11,466] INFO [Log partition=__cluster_metadata-0, dir=/tmp/kraft-combined-logs] Loading producer state till offset 0 with message format version 2 (kafka.log.Log)
   [2021-02-26 15:37:11,509] INFO [raft-expiration-reaper]: Starting (kafka.raft.TimingWheelExpirationService$ExpiredOperationReaper)
   [2021-02-26 15:37:11,640] INFO [RaftManager nodeId=1] Completed transition to Unattached(epoch=0, voters=[1], electionTimeoutMs=9037) (org.apache.kafka.raft.QuorumState)
   ...
   ```

