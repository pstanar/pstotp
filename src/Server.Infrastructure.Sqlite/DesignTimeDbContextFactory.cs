using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;
using PsTotp.Server.Infrastructure.Data;

namespace PsTotp.Server.Infrastructure.Sqlite;

public class DesignTimeDbContextFactory : IDesignTimeDbContextFactory<AppDbContext>
{
    public AppDbContext CreateDbContext(string[] args)
    {
        var optionsBuilder = new DbContextOptionsBuilder<AppDbContext>();
        optionsBuilder.UseSqlite("Data Source=pstotp_design.db",
            o => o.MigrationsAssembly(typeof(DesignTimeDbContextFactory).Assembly.GetName().Name));
        return new AppDbContext(optionsBuilder.Options);
    }
}
