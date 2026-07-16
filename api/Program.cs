using RailLog.API.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddSingleton<RailLogDatabase>();
builder.Services.Configure<EmailOptions>(builder.Configuration.GetSection("Email"));
builder.Services.AddSingleton<EmailSender>();
builder.Services.AddSingleton<EmailVerificationService>();
builder.Services.AddMemoryCache();
builder.Services.Configure<UpdateOptions>(builder.Configuration.GetSection("Updates"));
builder.Services.AddHttpClient<GitHubReleaseService>(client =>
{
    client.BaseAddress = new Uri("https://api.github.com/");
    client.DefaultRequestHeaders.UserAgent.ParseAdd("RailLog-Update-Service/1.0");
    client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
});
builder.Services
    .AddAuthentication(TokenAuthenticationHandler.SchemeName)
    .AddScheme<TokenAuthenticationOptions, TokenAuthenticationHandler>(
        TokenAuthenticationHandler.SchemeName,
        _ => { });
builder.Services.AddAuthorization();
builder.Services.AddCors(options => options.AddDefaultPolicy(policy =>
{
    if (builder.Environment.IsDevelopment())
    {
        policy.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod();
        return;
    }
    var origins = builder.Configuration
        .GetSection("Cors:AllowedOrigins")
        .Get<string[]>() ?? [];
    policy.WithOrigins(origins).AllowAnyHeader().AllowAnyMethod();
}));
builder.Services.AddControllers();

var app = builder.Build();

await app.Services.GetRequiredService<RailLogDatabase>().InitializeAsync();

app.UseCors();
app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();

app.Run();
