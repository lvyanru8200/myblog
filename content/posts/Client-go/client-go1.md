---
title: "client-go第一篇"
subtitle: ""
date: 2022-07-19T22:00:21+08:00
lastmod: 2022-07-19T22:00:21+08:00
draft: true
author: ""
authorLink: ""
description: ""
license: "整挺好许可"
images: []

tags: ["client-go"]
categories: ["client-go"]

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
> 1. client-go源码学习系列，写到博客中，一为定个小目标监督自己学习，二为留下记录，防止长时间不用某些知识而忘记。 
> 2. 本章节是client-go系列的第一个章节，准备将client-go源码学习一边，记录下来。


### 背景：

1. client-go学习的是1.24版本对应k8s `1.24`版本
2. 以前版本没细致的读过不知道1.24版本相较于以前的版本有没有大的变化

### 目录结构：

<div align=center>
<img src="/images/1.png" />
</div>

| 包                  | 作用                                    |
|--------------------|---------------------------------------|
| applyconfigurations | 1.24版本kubernetes中所有资源对象的所有版本的结构体。     |
| discovery          | discovery客户端API                       |
| dynamic            | dynamic客户端API                         |
| informers          | 1.24版本kubernetes中所有资源对象的informer实现    |
| kubernetes         | clientSet客户端API                       |
| listers            | 1.24版本kubernetes中所有资源对象的所有版本的lister实现 |
| metadata           | 用于获取GVR对应的metadata                    |
| openapi            |                                       |
| pkg                |                                       |
| plugin             |                                       |
| rest               | rest客户端API                            |
| restmapper         |                                       |
| scale              | scale客户端API                           |
| third_party        |                                       |
| tools              |                                       |
| transport          |                                       |
| util               |                                       |

### 本章主旨
> 😅 Client-go rest包阅读

<div align=center>
<img src="/images/2.png" />
</div>

> 😅 client-go感觉就是一个k8s工具包集合，提供了各种k8s客户端，阅读rest包，我大体看了下，感觉应该从client.go文件开始。

- **client.go**
    ```go
    // NewRESTClient
    //  @Description: 返回通过k8s RestAPI
    //  @param baseURL k8s服务器URL，格式为[scheme:][//[userinfo@]host][/]path[?query][#fragment]
    //  @param versionedAPIPath api路径
    //  @param config RESTClient与服务器通信序列化的配置
    //  @param rateLimiter 与ApiServer交互的request的速率限制
    //  @param client http请求的客户端配置
    //  @return *RESTClient
    //  @return error
    func NewRESTClient(
      baseURL *url.URL,
      versionedAPIPath string, 
      config ClientContentConfig, 
      rateLimiter flowcontrol.RateLimiter, 
      client *http.Client) (*RESTClient, error) {
      if len(config.ContentType) == 0 {
        config.ContentType = "application/json"
      }

      base := *baseURL
      if !strings.HasSuffix(base.Path, "/") {
        base.Path += "/"
      }
      base.RawQuery = ""
      base.Fragment = ""
      return &RESTClient{
        base:             &base,
        versionedAPIPath: versionedAPIPath,
        content:          config,
        createBackoffMgr: readExpBackoffConfig,
        rateLimiter:      rateLimiter,
        Client: client,
       }, nil
    }
    ```
  > RESTClient是对http.client的封装，为了更方便的请求apiserver的API
  ```go
  // NewRESTClient()返回一个RESTClient结构体，看下这个结构体
  type RESTClient struct {
      // 使用RestClient调用的跟url，应该是kubernets apiserver的服务器地址
      base *url.URL
      // 请求某个资源在baseurl候拼接的某资源的版本
      versionedAPIPath string
      // 与服务器之间的解码编码设置
      content ClientContentConfig
      // 返回值为BackoffManager接口类型的匿名方法，该接口主要定义了request请求和apiserver交互出现异常的处理办法
      createBackoffMgr func() BackoffManager
      // 一个在该客户端创建的所有请求之间共享的速率配置接口
      rateLimiter flowcontrol.RateLimiter
      // 一个在该客户端创建的所有请求之间共享的warn处理接口
      warningHandler WarningHandler
      // http客户端设置
      Client *http.Client
  }
  ```
  <div align=center>
  <img src="/images/3.png" />
  </div>
  
  ```go
  type Interface interface {
    // RESTClient中有一个全局的请求速率配置，get方法
    GetRateLimiter() flowcontrol.RateLimiter
    // 用于构建请求的操作动作的，GET，POST，PUT，DELETE
    Verb(verb string) *Request
    // 内部是.Verb("POST")
    Post() *Request
    Put() *Request
    // patch有些差异在请求头中设置Content-Type
    Patch(pt types.PatchType) *Request
    Get() *Request
    Delete() *Request
    // 获取GV
    APIVersion() schema.GroupVersion
  }
  ```