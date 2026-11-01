using Microsoft.EntityFrameworkCore;
using Mdm.Backend.Core.Entities;

namespace Mdm.Backend.Infrastructure.Data;

public class MdmDbContext : DbContext
{
    public MdmDbContext(DbContextOptions<MdmDbContext> options) : base(options)
    {
    }

    public DbSet<Family> Families => Set<Family>();
    public DbSet<ChildDevice> ChildDevices => Set<ChildDevice>();
    public DbSet<DevicePolicy> DevicePolicies => Set<DevicePolicy>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.Entity<Family>()
            .HasMany(f => f.Devices)
            .WithOne()
            .HasForeignKey(d => d.FamilyId)
            .OnDelete(DeleteBehavior.Cascade);

        modelBuilder.Entity<ChildDevice>()
            .HasOne(d => d.Policy)
            .WithOne()
            .HasForeignKey<DevicePolicy>(p => p.ChildDeviceId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
