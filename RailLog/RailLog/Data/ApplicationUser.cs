using Microsoft.AspNetCore.Identity;
using System.ComponentModel.DataAnnotations;

namespace RailLog.Data
{
    // Add profile data for application users by adding properties to the ApplicationUser class
    public class ApplicationUser : IdentityUser
    {
        [PersonalData]
        [StringLength(32, ErrorMessage = "用户名不能超过 32 个字符。")]
        public string? DisplayName { get; set; }

        [PersonalData]
        [StringLength(512, ErrorMessage = "头像链接长度不能超过 512 个字符。")]
        public string? AvatarUrl { get; set; }

        [PersonalData]
        [StringLength(200, ErrorMessage = "个人简介不能超过 200 个字符。")]
        public string? Bio { get; set; }

        [PersonalData]
        public bool ShowEmailOnProfile { get; set; }
    }

}
