using Mdm.Backend.Core.Entities;
using Mdm.Backend.Infrastructure.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Mdm.Backend.Api.Controllers;

[ApiController]
[Route("api/v1/[controller]")]
public class PairingController : ControllerBase
{
    private readonly MdmDbContext _dbContext;
    private readonly ILogger<PairingController> _logger;

    public PairingController(MdmDbContext dbContext, ILogger<PairingController> logger)
    {
        _dbContext = dbContext;
        _logger = logger;
    }

    public record RequestCodeDto(string DeviceName, string Model, int AndroidVersion);
    public record PairingCodeResponse(Guid DeviceId, string PairingOtp, string QrPayload, DateTime ExpiresAt);
    public record ClaimDto(string Otp, string FamilyName);
    public record ClaimResponse(Guid FamilyId, Guid DeviceId, string DeviceName, string Token);

    /// <summary>
    /// Bước 1: Máy con (target-node) yêu cầu mã ghép nối
    /// </summary>
    [HttpPost("request-code")]
    public async Task<ActionResult<PairingCodeResponse>> RequestCode([FromBody] RequestCodeDto dto)
    {
        var random = new Random();
        var otp = random.Next(100000, 999999).ToString();
        var expiresAt = DateTime.UtcNow.AddMinutes(5);

        var device = new ChildDevice
        {
            DeviceName = dto.DeviceName,
            Model = dto.Model,
            AndroidVersion = dto.AndroidVersion,
            Status = "PendingPairing",
            PairingOtp = otp,
            OtpExpiresAt = expiresAt,
            LastSeenAt = DateTime.UtcNow,
            Policy = new DevicePolicy
            {
                DailyScreenTimeMinutes = 120,
                BedtimeStart = "21:30",
                BedtimeEnd = "06:00"
            }
        };

        _dbContext.ChildDevices.Add(device);
        await _dbContext.SaveChangesAsync();

        var qrPayload = $"MDM:{device.Id}:{otp}";
        _logger.LogInformation("Generated pairing code for device {DeviceId}, OTP: {Otp}", device.Id, otp);

        return Ok(new PairingCodeResponse(device.Id, otp, qrPayload, expiresAt));
    }

    /// <summary>
    /// Bước 2: Máy phụ huynh (admin-node) quét QR hoặc nhập OTP để Claim quyền sở hữu
    /// </summary>
    [HttpPost("claim")]
    public async Task<ActionResult<ClaimResponse>> ClaimDevice([FromBody] ClaimDto dto)
    {
        var device = await _dbContext.ChildDevices
            .Include(d => d.Policy)
            .FirstOrDefaultAsync(d => d.PairingOtp == dto.Otp && d.OtpExpiresAt > DateTime.UtcNow);

        if (device == null)
        {
            return BadRequest(new { error = "Mã OTP không hợp lệ hoặc đã hết hạn." });
        }

        // Tạo hoặc lấy Family
        var family = await _dbContext.Families.FirstOrDefaultAsync();
        if (family == null)
        {
            family = new Family
            {
                Name = string.IsNullOrWhiteSpace(dto.FamilyName) ? "Gia Đình Mặc Định" : dto.FamilyName
            };
            _dbContext.Families.Add(family);
            await _dbContext.SaveChangesAsync();
        }

        device.FamilyId = family.Id;
        device.Status = "Active";
        device.PairingOtp = string.Empty; // Xóa OTP sau khi claim
        device.OtpExpiresAt = null;

        await _dbContext.SaveChangesAsync();
        _logger.LogInformation("Device {DeviceId} successfully claimed by Family {FamilyId}", device.Id, family.Id);

        var dummyJwt = $"MDM_TOKEN_{device.Id}_{family.Id}_{DateTime.UtcNow.Ticks}";
        return Ok(new ClaimResponse(family.Id, device.Id, device.DeviceName, dummyJwt));
    }
}
