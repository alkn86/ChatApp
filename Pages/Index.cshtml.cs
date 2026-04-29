using ChatApp.Data;
using ChatApp.Data.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.EntityFrameworkCore;

namespace ChatApp.Pages;

public class IndexModel(AppDbContext db) : PageModel
{
    public List<Room> Rooms { get; set; } = [];
    public string? Username { get; set; }

    [BindProperty]
    public string? NewUsername { get; set; }

    [BindProperty]
    public string? NewRoomName { get; set; }

    public async Task OnGetAsync()
    {
        Username = Request.Cookies["ChatUsername"];
        if (Username != null)
            Rooms = await db.Rooms.OrderBy(r => r.Name).ToListAsync();
    }

    public IActionResult OnGetClearUsername()
    {
        Response.Cookies.Delete("ChatUsername");
        return RedirectToPage();
    }

    public IActionResult OnPostSetUsername()
    {
        if (string.IsNullOrWhiteSpace(NewUsername))
        {
            ModelState.AddModelError(nameof(NewUsername), "Username is required.");
            return Page();
        }

        var sanitized = NewUsername.Trim();
        if (sanitized.Length > 30)
            sanitized = sanitized[..30];

        Response.Cookies.Append("ChatUsername", sanitized, new CookieOptions
        {
            Expires = DateTimeOffset.UtcNow.AddYears(1),
            IsEssential = true
        });

        return RedirectToPage();
    }

    public async Task<IActionResult> OnPostCreateRoomAsync()
    {
        if (string.IsNullOrWhiteSpace(NewRoomName))
        {
            ModelState.AddModelError(nameof(NewRoomName), "Room name is required.");
            Username = Request.Cookies["ChatUsername"];
            Rooms = await db.Rooms.OrderBy(r => r.Name).ToListAsync();
            return Page();
        }

        var name = NewRoomName.Trim();
        if (!await db.Rooms.AnyAsync(r => r.Name == name))
        {
            db.Rooms.Add(new Room { Name = name });
            await db.SaveChangesAsync();
        }

        var room = await db.Rooms.FirstAsync(r => r.Name == name);
        return RedirectToPage("/Chat", new { id = room.Id });
    }
}
