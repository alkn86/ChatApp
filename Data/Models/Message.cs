namespace ChatApp.Data.Models;

public class Message
{
    public int Id { get; set; }
    public int RoomId { get; set; }
    public Room Room { get; set; } = null!;
    public string Username { get; set; } = string.Empty;
    public string? Content { get; set; }
    public string? ImagePath { get; set; }
    public DateTime SentAt { get; set; } = DateTime.UtcNow;
}
