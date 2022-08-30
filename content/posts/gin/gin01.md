---
title: "Gin01"
subtitle: ""
date: 2022-08-01T14:55:37+08:00
lastmod: 2022-08-01T14:55:37+08:00
draft: true
author: "整挺好"
authorLink: ""
description: ""
license: "整挺好许可"
images: []

tags: ["Gin"]
categories: ["Gin"]

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

- Gin 1.8.1版本源码阅读。
- 一直在用gin写web，没读过代码只知道他是fasthttp的封装，所以先看下他的代码，再读读fasthttp。

### 正文：

- gin.go

从最简单的开始，一般在使用的时候直接gin.default(),gin.run()，先看下default()方法

```go
// default方法返回一个gin中定义的Engine结构体指针，先继续向下看
func Default() *Engine {
  // 打印一些环境变量
   debugPrintWARNINGDefault()
  // 新建Engine结构体
   engine := New()
  // 调用Engine的Use方法，传入Logger方法与Recovery方法
   engine.Use(Logger(), Recovery())
  // 返回engine结构体
   return engine
}
```

从上面这个方法看下来，那其实gin的主体还在于Engine结构体，看下Engine结构体

```go
type Engine struct {
  // 看名字是路由组，后面在看。
   RouterGroup
	// 看名字也能出来意思，是否重定向带有尾部斜线的路径，意思就是如果请求路径以/foo/结尾，但是没有/foo/的路由处理方法，有/foo结尾的，是否重定向到/foo结尾的处理方法，反之亦然。
   RedirectTrailingSlash bool
  // 看名称是重定向固定路径，意思就是如果请求的路径是..//foo是否自动修复为/foo执行/foo的处理方法。
   RedirectFixedPath bool
	// 看名称也能猜出来，是否检查请求路由是否允许这个这个请求路由的处理方法，如果该路由有处理方法，但是不允许，则使用405应答。如果其他所有情况，则直接notfound
   HandleMethodNotAllowed bool

  // 客户端IP获取的方式，是否从Engine的RemoteIPHeaders头中获取客户端IP
   ForwardedByClientIP bool
  // 弃用了
   AppEngine bool

   //如果为true则使用Url.rawpath来获取参数
   UseRawPath bool
	 // 如果为true则使用url.path获取参数
   UnescapePathValues bool
  // 路径中含有//:myparam// 这种请求是否解析参数
   RemoveExtraSlash bool
	// 当ForwardedByClientIP是true，这里放客户端Ip
   RemoteIPHeaders []string

   // TrustedPlatform if set to a constant of value gin.Platform*, trusts the headers set by
   // that platform, for example to determine the client IP
   TrustedPlatform string

	//maxMemory参数的值(http.Request的ParseMultipartForm调用时的参数)
   MaxMultipartMemory int64

   //开启h2c支持
   UseH2C bool

  // 当context.requets.context()不为空，则调用Context.Deadline()、Context.Done()、Context.Err() 和 Context.Value()
   ContextWithFallback bool
	// 分隔符(render.Delims表示使用HTML渲染的一组左右分隔符,具体可见html/template库)
   delims           render.Delims
  // 设置在Context.SecureJSON中国的json前缀
   secureJSONPrefix string
 //  返回一个HTMLRender接口(用于渲染HTMLProduction和HTMLDebug两个结构体类型的模板)
   HTMLRender       render.HTMLRender
  // html/template包中的FuncMap map[string]interface{} ,用来定义从名称到函数的映射
   FuncMap          template.FuncMap
  // 复制一份全局的handlers，加上NoRoute处理方法
   allNoRoute       HandlersChain
  // 复制一份全局的handlers，加上NoMethod处理方法
   allNoMethod      HandlersChain
   // noroute方法用于自定404
   noRoute          HandlersChain
  // 自定405
   noMethod         HandlersChain
  // 这里定义了一个可以临时存取对象的集合(sync.Pool是线程安全的，主要用来缓存为使用的item以减少GC压力，使得创建高效且线程安全的空闲队列)
   pool             sync.Pool
  // 负责存储路由和handle方法的映射，采用的是Radix树的结构。
   trees            methodTrees
   maxParams        uint16
   maxSections      uint16
   trustedProxies   []string
   trustedCIDRs     []*net.IPNet
}
```

看下engine := New()的这个new()方法

```go
func New() *Engine {
  // 打印不必在意
   debugPrintWARNINGNew()
  // 创建Engine结构体
   engine := &Engine{
      RouterGroup: RouterGroup{
         Handlers: nil,
         basePath: "/",
         root:     true,
      },
      FuncMap:                template.FuncMap{},
      RedirectTrailingSlash:  true,
      RedirectFixedPath:      false,
      HandleMethodNotAllowed: false,
      ForwardedByClientIP:    true,
      RemoteIPHeaders:        []string{"X-Forwarded-For", "X-Real-IP"},
      TrustedPlatform:        defaultPlatform,
      UseRawPath:             false,
      RemoveExtraSlash:       false,
      UnescapePathValues:     true,
      MaxMultipartMemory:     defaultMultipartMemory,
     // map中存储路由和处理函数的映射关系
      trees:                  make(methodTrees, 0, 9),
      delims:                 render.Delims{Left: "{{", Right: "}}"},
      secureJSONPrefix:       "while(1);",
      trustedProxies:         []string{"0.0.0.0/0", "::/0"},
      trustedCIDRs:           defaultTrustedCIDRs,
   }
   engine.RouterGroup.engine = engine
   engine.pool.New = func() any {
      return engine.allocateContext()
   }
   return engine
}
```

new方法构建出一个engine结构体返回，其中还有routergroup等，等到下面看到这里的时候在说明

可以看出Default()方法十分简单，看下engine.run()方法

```go
func (engine *Engine) Run(addr ...string) (err error) {
   defer func() { debugPrintError(err) }()
		
   if engine.isUnsafeTrustedProxies() {
      debugPrint("[WARNING] You trusted all proxies, this is NOT safe. We recommend you to set a value.\n" +
         "Please check https://pkg.go.dev/github.com/gin-gonic/gin#readme-don-t-trust-all-proxies for details.")
   }
  // resolveaddress方法根据传入的addr的长度判断，如果是0，则返回PORT环境变量的值，如果没有则返回:8080，addr虽然是一个切片，但是其实只允许传入一个值，如果多了会报错
   address := resolveAddress(addr)
   debugPrint("Listening and serving HTTP on %s\n", address)
  // 随后调用ListenAndServe方法，就是golang http包的listenandserver方法监听指定端口
   err = http.ListenAndServe(address, engine.Handler())
   return
}
```

gin中对于中间件的使用有两种方式，一种是全局的一种是对应于路由组的

对于全局的：

```go
func (engine *Engine) Use(middleware ...HandlerFunc) IRoutes {
  // 全局的话是调用engine中定义的路由组的use方式
   engine.RouterGroup.Use(middleware...)
  // rebuild404handlers方法中，主要是用engine的noRoute替换engine的allNoroute而allNoroute则是engine的group方法拼接上noroute的处理方法
   engine.rebuild404Handlers()
  // 与404同理
   engine.rebuild405Handlers()
   return engine
}
func (group *RouterGroup) Use(middleware ...HandlerFunc) IRoutes {
	group.Handlers = append(group.Handlers, middleware...)
	return group.returnObj()
}
```

对于routegroup的

```go
func (group *RouterGroup) Group(relativePath string, handlers ...HandlerFunc) *RouterGroup {
	return &RouterGroup{
		Handlers: group.combineHandlers(handlers),
		basePath: group.calculateAbsolutePath(relativePath),
		engine:   group.engine,
	}
}
```

gin的一个简单的使用过程就是这么多了，我们现在详细看下第二步构建engine结构体

```go
// RouterGroup结构体，定义了HandlersChain切片，这个切片中存放的应该就是各种handler处理方法
type RouterGroup struct {
   Handlers HandlersChain
  // basePath方法中定义基本路径
   basePath string
  // engine就是对应的engine
   engine   *Engine
  // root设置是否是根engine
   root     bool
}
```

