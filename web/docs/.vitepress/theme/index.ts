import DefaultTheme from 'vitepress/theme'
import { h } from 'vue'
import type { Theme } from 'vitepress'
import SiteFooter from './SiteFooter.vue'
import './custom.css'

export default {
    extends: DefaultTheme,
    Layout: () =>
        h(DefaultTheme.Layout, null, {
            'layout-bottom': () => h(SiteFooter),
        }),
} satisfies Theme
