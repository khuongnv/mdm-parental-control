namespace Mdm.Backend.Core.Entities;

public class Family
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public List<ChildDevice> Devices { get; set; } = new();
}

public class ChildDevice
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid FamilyId { get; set; }
    public string DeviceName { get; set; } = string.Empty;
    public string Model { get; set; } = string.Empty;
    public int AndroidVersion { get; set; }
    public string Status { get; set; } = "Active"; // Active, Suspended, Revoked
    public string PairingOtp { get; set; } = string.Empty;
    public DateTime? OtpExpiresAt { get; set; }
    public DateTime LastSeenAt { get; set; } = DateTime.UtcNow;
    public DevicePolicy? Policy { get; set; }
}

public class DevicePolicy
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid ChildDeviceId { get; set; }
    public int DailyScreenTimeMinutes { get; set; } = 120;
    public string BedtimeStart { get; set; } = "21:30";
    public string BedtimeEnd { get; set; } = "06:00";
    public bool IsEmergencyLockdown { get; set; } = false;
    public long PolicyVersion { get; set; } = 1;
    public string ETag { get; set; } = Guid.NewGuid().ToString("N");
    public List<string> BlacklistedPackages { get; set; } = new();
    public List<string> WhitelistedPackages { get; set; } = new();
}
