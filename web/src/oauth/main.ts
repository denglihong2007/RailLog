import './oauth.css'

import { createApp } from 'vue'
import OAuthApp from './OAuthApp.vue'

document.title = '授权 - RailLog 轨记'

createApp(OAuthApp).mount('#oauth-app')
