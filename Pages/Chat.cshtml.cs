using ChatApp.Data;
using ChatApp.Data.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.EntityFrameworkCore;

namespace ChatApp.Pages;

[IgnoreAntiforgeryToken]
[RequestSizeLimit(6_000_000)]
public class ChatModel(AppDbContext db, IWebHostEnvironment env) : PageModel
{
    public Room? Room { get; set; }
    public List<Message> RecentMessages { get; set; } = [];
    public string? Username { get; set; }

    public async Task<IActionResult> OnGetAsync(int id)
    {
        Username = Request.Cookies["ChatUsername"];
        if (Username == null)
            return RedirectToPage("/Index");

        Room = await db.Rooms.FindAsync(id);
        if (Room == null)
            return NotFound();

        RecentMessages = await db
            .Messages.Where(m => m.RoomId == id)
            .OrderBy(m => m.SentAt)
            //.TakeLast(100)
            .ToListAsync();

        return Page();
    }

    public async Task<IActionResult> OnPostUploadPhotoAsync(int id, IFormFile photo)
    {
        if (Request.Cookies["ChatUsername"] == null)
            return Unauthorized();

        if (await db.Rooms.FindAsync(id) == null)
            return NotFound();

        if (photo == null || photo.Length == 0)
            return BadRequest("No file provided.");

        if (photo.Length > 5 * 1024 * 1024)
            return BadRequest("File exceeds 5 MB limit.");

        var allowedExts = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            ".jpg",
            ".jpeg",
            ".png",
            ".gif",
            ".webp",
        };
        var allowedMimes = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "image/jpeg",
            "image/png",
            "image/gif",
            "image/webp",
        };

        var ext = Path.GetExtension(photo.FileName);
        if (!allowedExts.Contains(ext) || !allowedMimes.Contains(photo.ContentType))
            return BadRequest("Invalid file type.");

        var uploadsDir = Path.Combine(env.WebRootPath, "uploads");
        Directory.CreateDirectory(uploadsDir);

        var fileName = $"{Guid.NewGuid()}{ext}";
        var filePath = Path.Combine(uploadsDir, fileName);

        await using (var stream = System.IO.File.Create(filePath))
        {
            await photo.CopyToAsync(stream);
        }

        return new JsonResult(new { imagePath = $"/uploads/{fileName}" });
    }
}
