using ChatApp.Data;
using ChatApp.Data.Models;
using Microsoft.AspNetCore.SignalR;

namespace ChatApp.Hubs;

public class ChatHub(AppDbContext db) : Hub
{
    public async Task JoinRoom(int roomId)
    {
        await Groups.AddToGroupAsync(Context.ConnectionId, $"room_{roomId}");
    }

    public async Task LeaveRoom(int roomId)
    {
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"room_{roomId}");
    }

    public async Task SendMessage(int roomId, string? content, string? imagePath = null)
    {
        var hasContent = !string.IsNullOrWhiteSpace(content);
        var hasImage = !string.IsNullOrEmpty(imagePath);

        if (!hasContent && !hasImage)
            return;

        if (hasImage && !IsValidUploadPath(imagePath!))
            return;

        var username = Context.GetHttpContext()?.Request.Cookies["ChatUsername"] ?? "Anonymous";
        var message = new Message
        {
            RoomId = roomId,
            Username = username,
            Content = hasContent ? content!.Trim() : null,
            ImagePath = hasImage ? imagePath : null,
            SentAt = DateTime.UtcNow,
        };
        db.Messages.Add(message);
        await db.SaveChangesAsync();

        await Clients
            .Group($"room_{roomId}")
            .SendAsync(
                "ReceiveMessage",
                message.Username,
                message.Content,
                message.SentAt.ToString("HH:mm"),
                message.ImagePath
            );
    }

    private static bool IsValidUploadPath(string path) =>
        path.StartsWith("/uploads/", StringComparison.OrdinalIgnoreCase)
        && !path.Contains("..")
        && Path.GetFileName(path).Length > 0;
}
