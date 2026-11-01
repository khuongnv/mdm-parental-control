using Microsoft.AspNetCore.SignalR;

namespace Mdm.Backend.Api.Hubs;

public interface IMdmClient
{
    Task ReceivePanicLockdown(bool enable);
    Task ReceiveExtraTime(int minutes);
    Task ReceivePolicyUpdated(string etag, long version);
    Task ReceiveForceSync();
}

public class MdmHub : Hub<IMdmClient>
{
    private readonly ILogger<MdmHub> _logger;

    public MdmHub(ILogger<MdmHub> logger)
    {
        _logger = logger;
    }

    public async Task RegisterChildDevice(string deviceId)
    {
        await Groups.AddToGroupAsync(Context.ConnectionId, $"device_{deviceId}");
        _logger.LogInformation("Child device {DeviceId} joined group", deviceId);
    }

    public async Task RegisterParent(string familyId)
    {
        await Groups.AddToGroupAsync(Context.ConnectionId, $"family_{familyId}");
        _logger.LogInformation("Parent joined family group {FamilyId}", familyId);
    }

    public async Task TriggerPanicLockdown(string deviceId, bool lockState)
    {
        _logger.LogWarning("Parent triggered Panic Lockdown for device {DeviceId}: {LockState}", deviceId, lockState);
        await Clients.Group($"device_{deviceId}").ReceivePanicLockdown(lockState);
    }

    public async Task GrantExtraTime(string deviceId, int minutes)
    {
        _logger.LogInformation("Parent granted {Minutes} extra minutes to device {DeviceId}", minutes, deviceId);
        await Clients.Group($"device_{deviceId}").ReceiveExtraTime(minutes);
    }
}
