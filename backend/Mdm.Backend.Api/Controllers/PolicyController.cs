using Mdm.Backend.Api.Hubs;
using Mdm.Backend.Infrastructure.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;

namespace Mdm.Backend.Api.Controllers;

[ApiController]
[Route("api/v1/[controller]")]
public class PolicyController : ControllerBase
{
    private readonly MdmDbContext _dbContext;
    private readonly IHubContext<MdmHub, IMdmClient> _hubContext;
    private readonly ILogger<PolicyController> _logger;

    public PolicyController(
        MdmDbContext dbContext,
        IHubContext<MdmHub, IMdmClient> hubContext,
        ILogger<PolicyController> logger)
    {
        _dbContext = dbContext;
        _hubContext = hubContext;
        _logger = logger;
    }

    public record UpdatePolicyDto(
        int DailyScreenTimeMinutes,
        string BedtimeStart,
        string BedtimeEnd,
        bool IsEmergencyLockdown,
        List<string>? BlacklistedPackages,
        List<string>? WhitelistedPackages);

    [HttpGet("device/{deviceId}")]
    public async Task<IActionResult> GetDevicePolicy(Guid deviceId)
    {
        var device = await _dbContext.ChildDevices
            .Include(d => d.Policy)
            .FirstOrDefaultAsync(d => d.Id == deviceId);

        if (device == null || device.Policy == null)
        {
            return NotFound(new { error = "Không tìm thấy thiết bị hoặc chính sách." });
        }

        var policy = device.Policy;

        // ETag check
        var incomingEtag = Request.Headers.IfNoneMatch.ToString().Trim('\"');
        if (!string.IsNullOrEmpty(incomingEtag) && incomingEtag == policy.ETag)
        {
            return StatusCode(StatusCodes.Status304NotModified);
        }

        Response.Headers.ETag = $"\"{policy.ETag}\"";
        return Ok(policy);
    }

    [HttpPut("device/{deviceId}")]
    public async Task<IActionResult> UpdateDevicePolicy(Guid deviceId, [FromBody] UpdatePolicyDto dto)
    {
        var device = await _dbContext.ChildDevices
            .Include(d => d.Policy)
            .FirstOrDefaultAsync(d => d.Id == deviceId);

        if (device == null || device.Policy == null)
        {
            return NotFound(new { error = "Không tìm thấy thiết bị hoặc chính sách." });
        }

        var policy = device.Policy;
        policy.DailyScreenTimeMinutes = dto.DailyScreenTimeMinutes;
        policy.BedtimeStart = dto.BedtimeStart;
        policy.BedtimeEnd = dto.BedtimeEnd;
        policy.IsEmergencyLockdown = dto.IsEmergencyLockdown;
        if (dto.BlacklistedPackages != null) policy.BlacklistedPackages = dto.BlacklistedPackages;
        if (dto.WhitelistedPackages != null) policy.WhitelistedPackages = dto.WhitelistedPackages;

        policy.PolicyVersion++;
        policy.ETag = Guid.NewGuid().ToString("N");

        await _dbContext.SaveChangesAsync();
        _logger.LogInformation("Policy updated for device {DeviceId}, Version: {Version}, ETag: {ETag}", deviceId, policy.PolicyVersion, policy.ETag);

        // Real-time broadcast via SignalR (< 3s)
        await _hubContext.Clients.Group($"device_{deviceId}")
            .ReceivePolicyUpdated(policy.ETag, policy.PolicyVersion);

        if (dto.IsEmergencyLockdown)
        {
            await _hubContext.Clients.Group($"device_{deviceId}").ReceivePanicLockdown(true);
        }

        return Ok(policy);
    }
}
