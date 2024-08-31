{{$svrType := .ServiceType}}
{{$svrName := .ServiceName}}

{{- range .MethodSets}}
const Operation{{$svrType}}{{.OriginalName}} = "/{{$svrName}}/{{.OriginalName}}"
{{- end}}

type {{.ServiceType}}HTTPServer interface {
{{- range .MethodSets}}
	{{- if ne .Comment ""}}
	{{.Comment}}
	{{- end}}
	{{.Name}}(context.Context, *{{.Request}}) (*{{.Reply}}, error)
{{- end}}
}

type register{{.ServiceType}}HTTPResult struct{}

func (*register{{.ServiceType}}HTTPResult) String() string {
    return "{{.ServiceType}}HTTPServer"
}

func Register{{.ServiceType}}ServerHTTPProvider(newer interface{}) []interface{} {
	return []interface{}{
		// For provide dependency
		fx.Annotate(
			newer,
			fx.As(new({{.ServiceType}}HTTPServer)),
		),
		// For create instance
		fx.Annotate(
			register{{.ServiceType}}HTTPProviderImpl,
			fx.As(new(fmt.Stringer)),
			fx.ResultTags(`group:"http_register"`),
		),
	}
}

// register{{.ServiceType}}ProviderImpl use to trigger register
func register{{.ServiceType}}HTTPProviderImpl(s *http.Server, srv {{.ServiceType}}HTTPServer) *register{{.ServiceType}}HTTPResult {
	register{{.ServiceType}}HTTPServer(s, srv)
	return &register{{.ServiceType}}HTTPResult{}
}


func register{{.ServiceType}}HTTPServer(s *http.Server, srv {{.ServiceType}}HTTPServer) {
	r := s.Route("/")
	{{- range .Methods}}
	r.{{.Method}}("{{.Path}}", _{{$svrType}}_{{.Name}}{{.Num}}_HTTP_Handler(srv))
	{{- end}}
}

{{range .Methods}}
func _{{$svrType}}_{{.Name}}{{.Num}}_HTTP_Handler(srv {{$svrType}}HTTPServer) func(ctx http.Context) error {
	return func(ctx http.Context) error {
		var in {{.Request}}
		{{- if .HasBody}}
		if err := ctx.Bind(&in{{.Body}}); err != nil {
			return err
		}
		{{- end}}
		if err := ctx.BindQuery(&in); err != nil {
			return err
		}
		{{- if .HasVars}}
		if err := ctx.BindVars(&in); err != nil {
			return err
		}
		{{- end}}
		http.SetOperation(ctx,Operation{{$svrType}}{{.OriginalName}})
		h := ctx.Middleware(func(ctx context.Context, req interface{}) (interface{}, error) {
			return srv.{{.Name}}(ctx, req.(*{{.Request}}))
		})
		out, err := h(ctx, &in)
		if err != nil {
			return err
		}
		reply := out.(*{{.Reply}})
		return ctx.Result(200, reply{{.ResponseBody}})
	}
}
{{end}}

type {{.ServiceType}}HTTPClient interface {
{{- range .MethodSets}}
	{{.Name}}(ctx context.Context, req *{{.Request}}, opts ...http.CallOption) (rsp *{{.Reply}}, err error)
{{- end}}
	RegisterNameForDiscover() string

}

func register{{.ServiceType}}ClientHTTPNameProvider() []string {
	return []string{"{{.RegistryName}}", "http"}
}

func Register{{.ServiceType}}ClientHTTPProvider(creator interface{}) []interface{} {
	return []interface{}{
		fx.Annotate(
			new{{.ServiceType}}HTTPClient,
			fx.As(new({{.ServiceType}}HTTPClient)),
			fx.ParamTags(`name:"{{.RegistryName}}/http/{{.ServiceShortName}}"`),
		),
		fx.Annotate(
			creator,
			// fx.As(new(*http.Client)),
			fx.ParamTags(`name:"{{.RegistryName}}/http/name/{{.ServiceShortName}}"`),
			fx.ResultTags(`name:"{{.RegistryName}}/http/{{.ServiceShortName}}"`),
		),
		fx.Annotate(
			register{{.ServiceType}}ClientHTTPNameProvider,
			fx.ResultTags(`name:"{{.RegistryName}}/http/name/{{.ServiceShortName}}"`),
		),
	}
}

type {{.ServiceType}}HTTPClientFactory interface {
    New(conf *def.Server) ({{.ServiceType}}HTTPClient, error)
}

type _{{$svrType}}HTTPClientFactoryImpl struct {
    factory client.RegisterHTTPClientFactoryType
}

func (p *_{{$svrType}}HTTPClientFactoryImpl) New(conf *def.Server) ({{.ServiceType}}HTTPClient, error) {
    cc, err := p.factory(conf)
    if err != nil {
        return nil, fmt.Errorf("create {{.ServiceType}}HTTPClient failed cause %s", err)
    }

    return &_{{$svrType}}HTTPClientImpl { cc: cc }, nil
}

func Register{{.ServiceType}}HTTPClientFactoryProvider(factory client.RegisterHTTPClientFactoryType) {{.ServiceType}}HTTPClientFactory {
    return &_{{$svrType}}HTTPClientFactoryImpl{factory: factory}
}


type _{{.ServiceType}}HTTPClientImpl struct{
	cc *http.Client
}

func new{{.ServiceType}}HTTPClient (client *http.Client) {{.ServiceType}}HTTPClient {
	return &_{{.ServiceType}}HTTPClientImpl{client}
}

func (c *_{{$svrType}}HTTPClientImpl) RegisterNameForDiscover() string {
    return "{{.RegistryName}}"
}


{{range .MethodSets}}
func (c *_{{$svrType}}HTTPClientImpl) {{.Name}}(ctx context.Context, in *{{.Request}}, opts ...http.CallOption) (*{{.Reply}}, error) {
	var out {{.Reply}}
	pattern := "{{.Path}}"
	path := binding.EncodeURL(pattern, in, {{not .HasBody}})
	opts = append(opts, http.Operation(Operation{{$svrType}}{{.OriginalName}}))
	opts = append(opts, http.PathTemplate(pattern))
	{{if .HasBody -}}
	err := c.cc.Invoke(ctx, "{{.Method}}", path, in{{.Body}}, &out{{.ResponseBody}}, opts...)
	{{else -}}
	err := c.cc.Invoke(ctx, "{{.Method}}", path, nil, &out{{.ResponseBody}}, opts...)
	{{end -}}
	if err != nil {
		return nil, err
	}
	return &out, err
}
{{end}}
