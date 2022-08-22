---
title: "client-go第一篇"
subtitle: ""
date: 2022-07-19T22:00:21+08:00
lastmod: 2022-07-19T22:00:21+08:00
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
      // api路径
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

  ```go
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
  
  ```go
  // 需要看下clientContentConfig的Negotiator，这个接口主要是用来对GV进行编解码的
  func NewClientNegotiator(serializer NegotiatedSerializer, gv schema.GroupVersion) ClientNegotiator {
  	return &clientNegotiator{
  		serializer: serializer,
  		encode:     gv,
  	}
  }
  ```
  
  > 在config.go文件中还有一个InClusterConfig()方法，这个方法返回值为一个config指针，主要是用来如果我们与apiserver交互的应用程序在k8s环境中，则可使用此方法获取pod内存放的token以及ca证书，来构造出rest.config对象
  
  ```go
  func InClusterConfig() (*Config, error) {
     // pod中存放token与ca证书的地址
     const (
        tokenFile  = "/var/run/secrets/kubernetes.io/serviceaccount/token"
        rootCAFile = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
     )
     // 获取服务器apiserver地址以及端口
     host, port := os.Getenv("KUBERNETES_SERVICE_HOST"), os.Getenv("KUBERNETES_SERVICE_PORT")
     if len(host) == 0 || len(port) == 0 {
        return nil, ErrNotInCluster
     }
  	 // 获取token
     token, err := ioutil.ReadFile(tokenFile)
     if err != nil {
        return nil, err
     }
  	 
     tlsClientConfig := TLSClientConfig{}
  	 // 读取ca证书对应的pem内容
     if _, err := certutil.NewPool(rootCAFile); err != nil {
        klog.Errorf("Expected to load root CA config from %s, but got err: %v", rootCAFile, err)
     } else {
        tlsClientConfig.CAFile = rootCAFile
     }
  
     return &Config{
        // TODO: switch to using cluster DNS.
        Host:            "https://" + net.JoinHostPort(host, port),
        TLSClientConfig: tlsClientConfig,
        BearerToken:     string(token),
        BearerTokenFile: tokenFile,
     }, nil
  }
  ```
  
  
  
- **exec.go**

  > exec.go文件主要包含两个转化，ConfigToExecCluster() ExecClusterToConfig()，主要是为exec凭证插件配置提供服务的，没用过，不太懂，后面补上

- **request.go**

  > 主要看下request.go文件

  ```go
  // 开局声明了两个变量
  // 日志记录请求阈值，所有限速器设置了超过该时长的请求都会被记录
  longThrottleLatency = 50 * time.Millisecond
  // 日志级别为2的请求的阈值
  extraLongThrottleLatency = 1 * time.Second
  ```

  > 还是先用newRequest()方法看

  ```go
  // newrequest方法需要传入一个RestClient，返回一个request结构体指针
  func NewRequest(c *RESTClient) *Request {
    // 首先定义请求异常处理接口，restClient中定义了那么就创建
  	var backoff BackoffManager
  	if c.createBackoffMgr != nil {
  		backoff = c.createBackoffMgr()
  	}
  	if backoff == nil {
  		backoff = noBackoff
  	}
  	// 如果定义了baseURL则将baseurl与apipath按照/拼接，没定义则直接使用/apis
  	var pathPrefix string
  	if c.base != nil {
  		pathPrefix = path.Join("/", c.base.Path, c.versionedAPIPath)
  	} else {
  		pathPrefix = path.Join("/", c.versionedAPIPath)
  	}
  	// 定义请求超时时间
  	var timeout time.Duration
  	if c.Client != nil {
  		timeout = c.Client.Timeout
  	}
  	// 构造reques结构体
  	r := &Request{
  		c:              c,
  		rateLimiter:    c.rateLimiter,
  		backoff:        backoff,
  		timeout:        timeout,
  		pathPrefix:     pathPrefix,
  		maxRetries:     10,
  		retryFn:        defaultRequestRetryFn,
  		warningHandler: c.warningHandler,
  	}
  	// 设置请求头
  	switch {
  	case len(c.content.AcceptContentTypes) > 0:
  		r.SetHeader("Accept", c.content.AcceptContentTypes)
  	case len(c.content.ContentType) > 0:
  		r.SetHeader("Accept", c.content.ContentType+", */*")
  	}
    // 结束构造
  	return r
  }
  ```

  > newResuest方法返回一个Request结构体，看下Request结构体

  ```go
  type Request struct {
  	c *RESTClient
  
  	warningHandler WarningHandler
  
  	rateLimiter flowcontrol.RateLimiter
  	backoff     BackoffManager
  	timeout     time.Duration
  	maxRetries  int
    // 上部分基本都是RestClient传入的
  
  	// 下半部分定义是对接apiserver的api
  	verb       string
  	pathPrefix string
  	subpath    string
  	params     url.Values
  	headers    http.Header
  
  	namespace    string
  	namespaceSet bool
  	resource     string
  	resourceName string
  	subresource  string
  
  	// request输出
  	err  error
  	body io.Reader
  
  	retryFn requestRetryFunc
  }
  ```

  > request通过Resource() 方法设置要访问的资源

  ```go
  // resource方法传入resource的类型，构造request，设置要访问的资源类型
  func (r *Request) Resource(resource string) *Request {
  	if r.err != nil {
  		return r
  	}
  	if len(r.resource) != 0 {
  		r.err = fmt.Errorf("resource already set to %q, cannot change to %q", r.resource, resource)
  		return r
  	}
    // 这里对resource名称进行验证，var NameMayNotBe = []string{".", ".."}，名称不能为.或者..，名称中不能有/或者%
  	if msgs := IsValidPathSegmentName(resource); len(msgs) != 0 {
  		r.err = fmt.Errorf("invalid resource %q: %v", resource, msgs)
  		return r
  	}
  	r.resource = resource
  	return r
  }
  ```

  > 对于某资源的子资源，使用SubResource方法进行设置

  ```go
  // subResource在resource()与suffix()之间设置
  func (r *Request) SubResource(subresources ...string) *Request {
     if r.err != nil {
        return r
     }
    // 拼接子资源,像是resource().SubResource().SubResource()这种是不允许的
     subresource := path.Join(subresources...)
     if len(r.subresource) != 0 {
        r.err = fmt.Errorf("subresource already set to %q, cannot change to %q", r.subresource, subresource)
        return r
     }
     // 验证子资源名称设置名称不允许为.或..，名称中不允许含有/或%
     for _, s := range subresources {
        if msgs := IsValidPathSegmentName(s); len(msgs) != 0 {
           r.err = fmt.Errorf("invalid subresource %q: %v", s, msgs)
           return r
        }
     }
     r.subresource = subresource
     return r
  }
  ```

  > resource方法进行resource类型的设置，通过name方法进行resource名称的设置

  ```go
  // name传入resource的名称
  func (r *Request) Name(resourceName string) *Request {
  	if r.err != nil {
  		return r
  	}
  	if len(resourceName) == 0 {
  		r.err = fmt.Errorf("resource name may not be empty")
  		return r
  	}
    // 不允许.resourceName().resourceName()这种设置
  	if len(r.resourceName) != 0 {
  		r.err = fmt.Errorf("resource name already set to %q, cannot change to %q", r.resourceName, resourceName)
  		return r
  	}
    // 验证
  	if msgs := IsValidPathSegmentName(resourceName); len(msgs) != 0 {
  		r.err = fmt.Errorf("invalid resource name %q: %v", resourceName, msgs)
  		return r
  	}
  	r.resourceName = resourceName
  	return r
  }
  ```

  > resource namespace的设置

  ```go
  func (r *Request) Namespace(namespace string) *Request {
  	if r.err != nil {
  		return r
  	}
    // 避免.namespace().namespace()这种调用
  	if r.namespaceSet {
  		r.err = fmt.Errorf("namespace already set to %q, cannot change to %q", r.namespace, namespace)
  		return r
  	}
    // 字段验证
  	if msgs := IsValidPathSegmentName(namespace); len(msgs) != 0 {
  		r.err = fmt.Errorf("invalid namespace %q: %v", namespace, msgs)
  		return r
  	}
  	r.namespaceSet = true
  	r.namespace = namespace
  	return r
  }
  ```

  > 对于post，put请求，body的传递

  ```go
  func (r *Request) Body(obj interface{}) *Request {
  	if r.err != nil {
  		return r
  	}
    // 判断传入的obj的类型
  	switch t := obj.(type) {
    // 对于string类型的body
  	case string:
      // 认为他传入的是一个文件地址，读取他，设置请求体
  		data, err := ioutil.ReadFile(t)
  		if err != nil {
  			r.err = err
  			return r
  		}
  		glogBody("Request Body", data)
  		r.body = bytes.NewReader(data)
  	case []byte:
      // 转化
  		glogBody("Request Body", t)
  		r.body = bytes.NewReader(t)
  	case io.Reader:
      // 直接发送
  		r.body = t
  	case runtime.Object:
  		// 如果是runtime.Obj，避免传递指针
  		if reflect.ValueOf(t).IsNil() {
  			return r
  		}
      // 序列化
  		encoder, err := r.c.content.Negotiator.Encoder(r.c.content.ContentType, nil)
  		if err != nil {
  			r.err = err
  			return r
  		}
  		data, err := runtime.Encode(encoder, t)
  		if err != nil {
  			r.err = err
  			return r
  		}
  		glogBody("Request Body", data)
  		r.body = bytes.NewReader(data)
      // 设置请求头
  		r.SetHeader("Content-Type", r.c.content.ContentType)
  	default:
  		r.err = fmt.Errorf("unknown type used for body: %+v", obj)
  	}
  	return r
  }
  ```

  > 继续向下看，再看下watch方法

  ```go
  // watch方法返回一个watch接口
  func (r *Request) Watch(ctx context.Context) (watch.Interface, error) {
  	// watch方法不对速率限制做判断
  	if r.err != nil {
  		return nil, r.err
  	}
  	
  	client := r.c.Client
  	if client == nil {
  		client = http.DefaultClient
  	}
  	// 对于超时或者eof错误进行特殊处理
  	isErrRetryableFunc := func(request *http.Request, err error) bool {
  		if net.IsProbableEOF(err) || net.IsTimeout(err) {
  			return true
  		}
  		return false
  	}
    // 设置最大重试次数
  	retry := r.retryFn(r.maxRetries)
  	url := r.URL().String()
    // 循环
  	for {
      // 重试策略，如果ctx已经被取消，无需重试，进行retryafter判断，每次请求会对RetryAfter结构体进行测试进行设置，如果为空，直接return nil，设置从头读取，根据配置的backoffmanager做处理
  		if err := retry.Before(ctx, r); err != nil {
  			return nil, retry.WrapPreviousError(err)
  		}
  		// 新建httprequest
  		req, err := r.newHTTPRequest(ctx)
  		if err != nil {
  			return nil, err
  		}
  		// 调用http do方法
  		resp, err := client.Do(req)
  		updateURLMetrics(ctx, r, resp, err)
      // 重试配置
  		retry.After(ctx, r, resp, err)
      // 如果请求ok则新建一个tcp长连接
  		if err == nil && resp.StatusCode == http.StatusOK {
        // 下方newStreamWatcher方法
  			return r.newStreamWatcher(resp)
  		}
  		
  		done, transformErr := func() (bool, error) {
  			defer readAndCloseResponseBody(resp)
  
  			if retry.IsNextRetry(ctx, r, req, resp, err, isErrRetryableFunc) {
  				return false, nil
  			}
  
  			if resp == nil {
  				// the server must have sent us an error in 'err'
  				return true, nil
  			}
  			if result := r.transformResponse(resp, req); result.err != nil {
  				return true, result.err
  			}
  			return true, fmt.Errorf("for request %s, got status: %v", url, resp.StatusCode)
  		}()
  		if done {
        // 如果是eof或者是超时，返回一个空的watch接口
  			if isErrRetryableFunc(req, err) {
  				return watch.NewEmptyWatch(), nil
  			}
  			if err == nil {
  				err = transformErr
  			}
  			return nil, retry.WrapPreviousError(err)
  		}
  	}
  }
  ```

  > 就是for了无数次没有错误的情况下，每次http请求，ok创建tcp长连接，解码body

  ```go
  func (r *Request) newStreamWatcher(resp *http.Response) (watch.Interface, error) {
  	contentType := resp.Header.Get("Content-Type")
  	mediaType, params, err := mime.ParseMediaType(contentType)
  	if err != nil {
  		klog.V(4).Infof("Unexpected content type from the server: %q: %v", contentType, err)
  	}
  	objectDecoder, streamingSerializer, framer, err := r.c.content.Negotiator.StreamDecoder(mediaType, params)
  	if err != nil {
  		return nil, err
  	}
  
  	handleWarnings(resp.Header, r.warningHandler)
  	// 读取resp的body 
  	frameReader := framer.NewFrameReader(resp.Body)
    // 解码frameReader的[]byte
  	watchEventDecoder := streaming.NewDecoder(frameReader, streamingSerializer)
  
  	return watch.NewStreamWatcher(
  		restclientwatch.NewDecoder(watchEventDecoder, objectDecoder),
  		errors.NewClientErrorReporter(http.StatusInternalServerError, r.verb, "ClientWatchDecoding"),
  	), nil
  }
  ```

  
