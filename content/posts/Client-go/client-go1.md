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

- **config.go**

  > Config.go文件同样从RESTClientFor()方法开始，RESTClientFor方法通过传入一个config结构体，构建出RESTClient客户端，所以先看下config结构体

  ```
  type Config struct {
    // apiserver的地址，host:port或者能到达apiserver的URL
  	Host string
  	// apiserver的api路径，/apis
  	APIPath string
  	// 编解码设置
  	ContentConfig
    // 服务器基本验证
  	Username string
  	Password string `datapolicy:"password"`
    // 服务器token验证
  	BearerToken string `datapolicy:"token"`
    // token文件地址，如果设置，则会定期读取该目录下的token值会覆盖BearerToken配置
  	BearerTokenFile string
  	// 
  	Impersonate ImpersonationConfig
  
  	// 用于认证的插件配置
  	AuthProvider *clientcmdapi.AuthProviderConfig
  	AuthConfigPersister AuthProviderConfigPersister
  
  	// exec方式身份验证
  	ExecProvider *clientcmdapi.ExecConfig
  
  	// 客户端tls配置
  	TLSClientConfig
  
  	// 指定调用者
  	UserAgent string
  
  	// 跳过服务器自动GZip压缩请求
  	DisableCompression bool
  
  	// Transport may be used for custom HTTP behavior. This attribute may not
  	// be specified with the TLS client certificate options. Use WrapTransport
  	// to provide additional per-server middleware behavior.
  	Transport http.RoundTripper
  	// WrapTransport will be invoked for custom HTTP behavior after the underlying
  	// transport is initialized (either the transport created from TLSClientConfig,
  	// Transport, or http.DefaultTransport). The config may layer other RoundTrippers
  	// on top of the returned RoundTripper.
  	//
  	// A future release will change this field to an array. Use config.Wrap()
  	// instead of setting this value directly.
  	WrapTransport transport.WrapperFunc
  
  	// 客户端到apiserver服务器的最大QPS，默认是5
  	QPS float32
  
  	// Maximum burst for throttle.
  	// If it's zero, the created RESTClient will use DefaultBurst: 10.
  	Burst int
  
  	// 该client到服务器的速率设置，存在则覆盖QPS和Burst
  	RateLimiter flowcontrol.RateLimiter
    // warning处理
  	WarningHandler WarningHandler
  
  	// 连接服务器超时时间
  	Timeout time.Duration
  
  	// 用于创建未加密TCP连接的拨号功能
  	Dial func(ctx context.Context, network, address string) (net.Conn, error)
  
  	// 如果为空，则为http.ProxyFromEnvironment
  	Proxy func(*http.Request) (*url.URL, error)
  }
  ```

  > config结构体有些字段看不太懂，整体看完后，将不太懂的一些字段补一下。
  >
  > 现在看一下RESTClientFor():

  ```go
  // RESTClientFor方法传入一个config结构体构建出RESTClient客户端
  func RESTClientFor(config *Config) (*RESTClient, error) {
    // 根据上面的RESTClient结构体知道实例化RESTClient需要versionedAPIPath以及content，所以要通过传入的config构建出RESTCLient结构体，就需要GroupVersion以及NegotiatedSerializer一个用来做versionAPIPath一个用来做序列化
  	if config.GroupVersion == nil {
  		return nil, fmt.Errorf("GroupVersion is required when initializing a RESTClient")
  	}
  	if config.NegotiatedSerializer == nil {
  		return nil, fmt.Errorf("NegotiatedSerializer is required when initializing a RESTClient")
  	}
  	// 这里主要是验证一下host，错误的话就不用走下去了
  	_, _, err := defaultServerUrlFor(config)
  	if err != nil {
  		return nil, err
  	}
  	// 这里通过config配置来构造出httpclient
  	httpClient, err := HTTPClientFor(config)
  	if err != nil {
  		return nil, err
  	}
  	return RESTClientForConfigAndClient(config, httpClient)
  }
  ```

  > 看下RESTClientForConfigAndClient()方法，他依然是传入config与上一步构造出来的http客户端

  ```go
  // RESTClientForConfigAndClient()方法也可以直接调用，他与RESTClientFor()的区别在于，ClientFor()方法的区别在于，clientFor
  // 方法中的httpclient只会对config提供的身份验证和传输安全性来构建httpclient，如果没设置，将返回一个默认的httpClient，而
  // RESTClientForConfigAndClient的httpClient则可传入一个全局的client
  func RESTClientForConfigAndClient(config *Config, httpClient *http.Client) (*RESTClient, error) {
  	if config.GroupVersion == nil {
  		return nil, fmt.Errorf("GroupVersion is required when initializing a RESTClient")
  	}
  	if config.NegotiatedSerializer == nil {
  		return nil, fmt.Errorf("NegotiatedSerializer is required when initializing a RESTClient")
  	}
  	// baseURL与apis
  	baseURL, versionedAPIPath, err := defaultServerUrlFor(config)
  	if err != nil {
  		return nil, err
  	}
  	// 如果配置了速率设置则使用配置的，如果没有配置或者配置的0.0则使用默认的5和10
  	rateLimiter := config.RateLimiter
  	if rateLimiter == nil {
  		qps := config.QPS
  		if config.QPS == 0.0 {
  			qps = DefaultQPS
  		}
  		burst := config.Burst
  		if config.Burst == 0 {
  			burst = DefaultBurst
  		}
  		if qps > 0 {
  			rateLimiter = flowcontrol.NewTokenBucketRateLimiter(qps, burst)
  		}
  	}
  	// 获取gv，apiserver中的所有group以及version
  	var gv schema.GroupVersion
    // 这里其实已经不需要判断了
  	if config.GroupVersion != nil {
  		gv = *config.GroupVersion
  	}
    // 构建编解码服务配置
  	clientContent := ClientContentConfig{
  		AcceptContentTypes: config.AcceptContentTypes,
  		ContentType:        config.ContentType,
  		GroupVersion:       gv,
  		Negotiator:         runtime.NewClientNegotiator(config.NegotiatedSerializer, gv),
  	}
    // 调用NewRESTClient()方法创建RESTClient
  	restClient, err := NewRESTClient(baseURL, versionedAPIPath, clientContent, rateLimiter, httpClient)
  	if err == nil && config.WarningHandler != nil {
  		restClient.warningHandler = config.WarningHandler
  	}
  	return restClient, err
  }
  ```

  > 当config中的GroupVerison不存在的时候，使用UnversionedRESTClientFor，UnversionedRESTClientForConfigAndClient两个方法，与上方两个方法唯一的区别就是没有GroupVerison == nil的判断。

