using AutoMapper;
using RailLog.Data;
using RailLog.Shared.Models;

namespace RailLog.Profiles;
public class MappingProfile : Profile
{
    public MappingProfile()
    {
        CreateMap<TripRecordDto, TripRecord>()
            .ForMember(dest => dest.Id, opt => opt.Ignore());
    }
}