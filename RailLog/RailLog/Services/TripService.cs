using Microsoft.EntityFrameworkCore;
using RailLog.Data;

namespace RailLog.Services
{
    public class TripService(ApplicationDbContext context)
    {
        public async Task SaveRecordAsync(TripRecord record)
        {
            context.TripRecords.Add(record);
            await context.SaveChangesAsync();
        }

        public async Task<List<TripRecord>> GetUserRecordsAsync(string userId)
        {
            return await context.TripRecords
                .Where(r => r.UserId == userId)
                .OrderByDescending(r => r.TravelDate)
                .ToListAsync();
        }

        public async Task<List<TripRecord>> GetUserTripsAsync(string userId)
        {
            return await context.TripRecords
                .Where(t => t.UserId == userId)
                .OrderByDescending(t => t.TravelDate) // 按日期倒序，最新的在前面
                .ToListAsync();
        }
    }
}
