import { defineConfig } from 'vitepress'

const siteOrigin = 'https://www.raillog.top'
const repoUrl = 'https://github.com/denglihong2007/RailLog'

export default defineConfig({
    lang: 'zh-CN',
    title: 'RailLog 开放 API',
    description: 'RailLog 开放 API v1 文档：铁路时刻表、搜索、评价、公开行程与用户信息。',
    base: '/api-docs/',
    outDir: '../dist/api-docs',
    cleanUrls: false,
    head: [
        ['link', { rel: 'icon', href: '/api-docs/raillog-icon.png' }],
        ['meta', { name: 'theme-color', content: '#b3261e' }],
        ['meta', { property: 'og:title', content: 'RailLog 开放 API' }],
        ['meta', { property: 'og:description', content: '免认证、只读的铁路时刻表与行程数据接口。' }],
    ],
    themeConfig: {
        logo: '/raillog-icon.png',
        siteTitle: 'RailLog 开放 API',
        nav: [
            { text: '概览', link: '/' },
            { text: '铁路时刻表', link: '/timetable' },
            { text: '搜索', link: '/search' },
            { text: '评价', link: '/reviews' },
            { text: '行程详情', link: '/trips' },
            { text: '用户信息', link: '/users' },
            {
                text: '官网',
                items: [
                    { text: '行程查询', link: `${siteOrigin}/trip` },
                    { text: '用户查询', link: `${siteOrigin}/user` },
                    { text: '下载 RailLog', link: `${siteOrigin}/download` },
                    { text: 'GitHub 仓库', link: repoUrl },
                ],
            },
        ],
        sidebar: [
            {
                text: '开始使用',
                items: [{ text: '概览与兼容性', link: '/' }],
            },
            {
                text: '公开接口',
                items: [
                    { text: '铁路时刻表', link: '/timetable' },
                    { text: '搜索', link: '/search' },
                    { text: '评价', link: '/reviews' },
                    { text: '行程详情', link: '/trips' },
                    { text: '用户信息', link: '/users' },
                ],
            },
            {
                text: '协议与支持',
                items: [{ text: '格式与错误', link: '/errors' }],
            },
        ],
        outline: { level: [2, 3], label: '本页目录' },
        search: {
            provider: 'local',
            options: {
                translations: {
                    button: {
                        buttonText: '搜索文档',
                        buttonAriaLabel: '搜索文档',
                    },
                    modal: {
                        noResultsText: '没有找到相关内容',
                        resetButtonTitle: '清除查询条件',
                        footer: {
                            selectText: '选择',
                            navigateText: '切换',
                            closeText: '关闭',
                        },
                    },
                },
            },
        },
        docFooter: { prev: '上一页', next: '下一页' },
        darkModeSwitchLabel: '外观',
        lightModeSwitchTitle: '切换到浅色模式',
        darkModeSwitchTitle: '切换到深色模式',
        sidebarMenuLabel: '文档目录',
        returnToTopLabel: '返回顶部',
        externalLinkIcon: true,
        lastUpdated: false,
    },
})
