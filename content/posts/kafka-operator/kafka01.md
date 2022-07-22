---
title: "Kafka01"
subtitle: ""
date: 2022-07-22T11:24:42+08:00
lastmod: 2022-07-22T11:24:42+08:00
draft: true
author: "整挺好"
authorLink: ""
description: ""
license: ""
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

#### 为什么要学习Kafka

本人目前作为一个Gopher，在日常中对自己或者对公司来说，基本上没有对Kafka的使用场景，但是从职业发展赚钱来看，Kafka貌似好像有必要一学，这是学习kafka的第一个原因，另外一个原因是大多数Gopher除了搞区块链的，感觉一半和k8s绑定一半和web绑定，本人正好是和k8s绑定的一只，目前我对自己的职业定位并不清楚，我自称为"砖"工程师，因为在工作中感觉自己就像一块砖，哪里需要哪里搬，干啥都可以，工作哪里需要就去哪里，扯远了，因为本人与k8s绑定的关系，同时目前也正在做中间件Operator开发的工作，目前聚焦在Kafka上，所以先学习下Kafka。

> 关于K8s Operator的开发，本人另有更新
>
> 同时，这个kafka系列中包含本人学习，Kafka Operator开发，Kafka 使用等一些学习过程

#### kafka 简介干啥的就不说了，没几把意思

#### 本文主旨：

- 手动部署kafka集群(zookeeper,kRaft两种)
- 手动创建Topic
- 手动创建User
- 手动进行Topic分区
- 写到这里后面还有的话补充一下这里....

