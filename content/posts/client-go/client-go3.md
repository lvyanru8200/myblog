---
title: "client-go第三篇"
subtitle: ""
date: 2022-08-22T11:25:37+08:00
lastmod: 2022-08-22T11:25:37+08:00
draft: true
author: "整挺好"
authorLink: "整挺好许可"
description: ""
license: ""
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

### 本文主旨：

discovery包阅读

### 正文：

- discovery_client.go

<div align=center>
  <img src="/images/18.png">
</div>

discovery_client.go文件依然是以一个接口开始，DiscoveryInterface，如下图：

<div align=center>
  <img src="/images/17.png">
</div>

DiscoveryInterface接口定义了一个RESTClient()方法以及5个接口，RESTClient接口仍然是返回rest接口好通过rest客户端去堆apiserver执行rest请求，而其他5个接口通过名称以及猜测就可以判断出应该是获取G/V/K/以及通过OpenAPI加入的自定义资源的GVK，以ServerGroupsInterface为例：

<div align=center>
  <img src="/images/19.png">
</div>

serverGroups()方法返回k8s的APIGroupList资源，看一下他的实现：

```go
func (d *DiscoveryClient) ServerGroups() (apiGroupList *metav1.APIGroupList, err error) {
   // Get the groupVersions exposed at /api
   v := &metav1.APIVersions{}
   // 这里使用rest客户端以及restapi中请求apiserver的api组的路径去获取（/api）
   err = d.restClient.Get().AbsPath(d.LegacyPrefix).Do(context.TODO()).Into(v)
   apiGroup := metav1.APIGroup{}
   if err == nil && len(v.Versions) != 0 {
      apiGroup = apiVersionsToAPIGroup(v)
   }
   if err != nil && !errors.IsNotFound(err) && !errors.IsForbidden(err) {
      return nil, err
   }

   // 这里使用rest客户端以及restapi中请求apiserver的api组的路径去获取（/apis）
   apiGroupList = &metav1.APIGroupList{}
   err = d.restClient.Get().AbsPath("/apis").Do(context.TODO()).Into(apiGroupList)
   if err != nil && !errors.IsNotFound(err) && !errors.IsForbidden(err) {
      return nil, err
   }
   // to be compatible with a v1.0 server, if it's a 403 or 404, ignore and return whatever we got from /api
   if err != nil && (errors.IsNotFound(err) || errors.IsForbidden(err)) {
      apiGroupList = &metav1.APIGroupList{}
   }

   // prepend the group retrieved from /api to the list if not empty
   if len(v.Versions) != 0 {
      apiGroupList.Groups = append([]metav1.APIGroup{apiGroup}, apiGroupList.Groups...)
   }
   return apiGroupList, nil
}
```

discovery客户端比较简单，就这么多，在实际中感觉也不怎么用这个客户端。
