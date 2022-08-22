---
title: "client-go第二篇"
subtitle: ""
date: 2022-08-22T10:18:00+08:00
lastmod: 2022-08-22T10:18:00+08:00
draft: true
author: "整挺好"
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

### 本文主旨：

kubernetes(clientset)包阅读

<div align=center>
  <img src="/images/10.png">
</div>

### 正文:

- clientset.go

<div align=center>
  <img src="/images/11.png">
</div>

<div align=center>
  <img src="/images/12.png">
</div>

clientset.go文件,首先定义了一个上图所示的Interface接口，这个接口中的方法首先，他按照组以及版本(GV)来区分k8s各类资源，然后每个GV方法的返回值为对应的GV接口，这些GV接口大同小异，每个GV接口中首先定义了一个RESTClient以及GV对应的不同资源类型(K)的Getter接口，这些Getter接口中定义了该K的CRUD等方法。

以AppsV1()为例：

首先，AppsV1()返回值为appsv1.AppsV1Interface:

<div align=center>
  <img src="/images/13.png">
</div>

AppsV1Interface接口，定义如下：

<div align=center>
  <img src="/images/14.png">
</div>

可以看到，该接口需要实现一个RESTClient()方法，而RESTClient方法返回的正是上一篇提到的Rest接口，除了RESTClient方法，下方还封装了对应GV的不同K的Getter接口，以DaemonSetsGetter接口为例：

<div align=center>
  <img src="/images/15.png">
</div>

DeamoSetsGetter接口中封装了对应ns的DaemonSets接口，该接口返回DeamonSet类型资源的CRUD等操作。

其他GV接口也是类型的逻辑。

Clientset结构体实现了该接口：

```go
type Clientset struct {
   *discovery.DiscoveryClient
   admissionregistrationV1      *admissionregistrationv1.AdmissionregistrationV1Client
   admissionregistrationV1beta1 *admissionregistrationv1beta1.AdmissionregistrationV1beta1Client
   internalV1alpha1             *internalv1alpha1.InternalV1alpha1Client
   appsV1                       *appsv1.AppsV1Client
   appsV1beta1                  *appsv1beta1.AppsV1beta1Client
   appsV1beta2                  *appsv1beta2.AppsV1beta2Client
   authenticationV1             *authenticationv1.AuthenticationV1Client
   authenticationV1beta1        *authenticationv1beta1.AuthenticationV1beta1Client
   authorizationV1              *authorizationv1.AuthorizationV1Client
   authorizationV1beta1         *authorizationv1beta1.AuthorizationV1beta1Client
   autoscalingV1                *autoscalingv1.AutoscalingV1Client
   autoscalingV2                *autoscalingv2.AutoscalingV2Client
   autoscalingV2beta1           *autoscalingv2beta1.AutoscalingV2beta1Client
   autoscalingV2beta2           *autoscalingv2beta2.AutoscalingV2beta2Client
   batchV1                      *batchv1.BatchV1Client
   batchV1beta1                 *batchv1beta1.BatchV1beta1Client
   certificatesV1               *certificatesv1.CertificatesV1Client
   certificatesV1beta1          *certificatesv1beta1.CertificatesV1beta1Client
   coordinationV1beta1          *coordinationv1beta1.CoordinationV1beta1Client
   coordinationV1               *coordinationv1.CoordinationV1Client
   coreV1                       *corev1.CoreV1Client
   discoveryV1                  *discoveryv1.DiscoveryV1Client
   discoveryV1beta1             *discoveryv1beta1.DiscoveryV1beta1Client
   eventsV1                     *eventsv1.EventsV1Client
   eventsV1beta1                *eventsv1beta1.EventsV1beta1Client
   extensionsV1beta1            *extensionsv1beta1.ExtensionsV1beta1Client
   flowcontrolV1alpha1          *flowcontrolv1alpha1.FlowcontrolV1alpha1Client
   flowcontrolV1beta1           *flowcontrolv1beta1.FlowcontrolV1beta1Client
   flowcontrolV1beta2           *flowcontrolv1beta2.FlowcontrolV1beta2Client
   networkingV1                 *networkingv1.NetworkingV1Client
   networkingV1beta1            *networkingv1beta1.NetworkingV1beta1Client
   nodeV1                       *nodev1.NodeV1Client
   nodeV1alpha1                 *nodev1alpha1.NodeV1alpha1Client
   nodeV1beta1                  *nodev1beta1.NodeV1beta1Client
   policyV1                     *policyv1.PolicyV1Client
   policyV1beta1                *policyv1beta1.PolicyV1beta1Client
   rbacV1                       *rbacv1.RbacV1Client
   rbacV1beta1                  *rbacv1beta1.RbacV1beta1Client
   rbacV1alpha1                 *rbacv1alpha1.RbacV1alpha1Client
   schedulingV1alpha1           *schedulingv1alpha1.SchedulingV1alpha1Client
   schedulingV1beta1            *schedulingv1beta1.SchedulingV1beta1Client
   schedulingV1                 *schedulingv1.SchedulingV1Client
   storageV1beta1               *storagev1beta1.StorageV1beta1Client
   storageV1                    *storagev1.StorageV1Client
   storageV1alpha1              *storagev1alpha1.StorageV1alpha1Client
```

clientset结构体中可以看到分别为上述接口中定义的GV接口的实现结构体，依然以appsV1为例：

<div align=center>
  <img src="/images/16.png">
</div>

appsv1结构体中定义了一个restClient接口，又和上文中的rest接口对应上了，那就可以得出，clientset接口只是将GV区分开然后对应不同的K通过ns以及RestClient调用rest的请求方法请求apiserver对资源进行CRUD等操作。

GV接口基本大同小异，看一下，ClientSet还实现了DiscoveryInterface接口，DiscoveryInterface接口中定义了如下方法：

<div align=center>
  <img src="/images/17.png">
</div>

可以看出来，discovery客户端主要是获取GVK以及OpenAPI资源的接口，在下文阅读DIscovery包是进行详细说明。
