using ChatApp.Data;
using ChatApp.Hubs;
using Microsoft.EntityFrameworkCore;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddRazorPages();
builder.Services.AddSignalR();
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlite(builder.Configuration.GetConnectionString("DefaultConnection") ?? "Data Source=chat.db"));

var app = builder.Build();

using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    db.Database.Migrate();
}

// Configure HTTPS/certificate in production
if (app.Environment.IsProduction())
{
    var certPath = builder.Configuration["Kestrel:Certificates:Default:Path"];
    var certPassword = builder.Configuration["Kestrel:Certificates:Default:Password"];

    if (!string.IsNullOrEmpty(certPath) && File.Exists(certPath))
    {
        app.Logger.LogInformation($"Loading certificate from {certPath}", certPath);
    }
}

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error");
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseRouting();
app.UseAuthorization();

app.MapStaticAssets();
app.MapRazorPages().WithStaticAssets();
app.MapHub<ChatHub>("/chathub");

app.Run();
