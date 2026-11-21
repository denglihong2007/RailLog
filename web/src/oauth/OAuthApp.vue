<script setup lang="ts">
import { onMounted, ref } from 'vue'
import {
  ArrowLeft,
  Eye,
  EyeOff,
  LoaderCircle,
  LockKeyhole,
  ShieldCheck,
} from '@lucide/vue'
import {
  ApiError,
  decide,
  fetchClient,
  login,
  readAuthorizeParams,
  type AuthorizeClient,
  type AuthorizeParams,
} from './api'

type Phase = 'loading' | 'invalid' | 'login' | 'consent' | 'redirecting'

const phase = ref<Phase>('loading')
const error = ref('')
const params = ref<AuthorizeParams | null>(null)
const client = ref<AuthorizeClient | null>(null)

const email = ref('')
const password = ref('')
const showPassword = ref(false)
const displayName = ref('')
const token = ref('')
const submitting = ref(false)

onMounted(() => {
  void initialize()
})

async function initialize(): Promise<void> {
  const parsed = readAuthorizeParams(window.location.search)
  if (!parsed) {
    phase.value = 'invalid'
    error.value = '授权链接不完整或已被修改，请回到万花筒重新发起授权。'
    return
  }
  params.value = parsed
  try {
    client.value = await fetchClient(parsed)
    phase.value = 'login'
  } catch (exception) {
    phase.value = 'invalid'
    error.value = describe(exception)
  }
}

async function submitLogin(): Promise<void> {
  if (submitting.value) return
  if (!email.value.trim()) {
    error.value = '请输入账户邮箱'
    return
  }
  if (!password.value) {
    error.value = '请输入密码'
    return
  }
  submitting.value = true
  error.value = ''
  try {
    const session = await login(email.value.trim(), password.value)
    token.value = session.token
    displayName.value = session.displayName
    password.value = ''
    phase.value = 'consent'
  } catch (exception) {
    error.value = describe(exception)
  } finally {
    submitting.value = false
  }
}

async function submitDecision(approved: boolean): Promise<void> {
  if (!params.value || !token.value || submitting.value) return
  submitting.value = true
  error.value = ''
  try {
    const redirectUrl = await decide(params.value, token.value, approved)
    phase.value = 'redirecting'
    window.location.assign(redirectUrl)
  } catch (exception) {
    if (exception instanceof ApiError && exception.status === 401) {
      token.value = ''
      displayName.value = ''
      phase.value = 'login'
      error.value = '登录已失效，请重新登录'
    } else {
      error.value = describe(exception)
    }
    submitting.value = false
  }
}

function describe(exception: unknown): string {
  if (exception instanceof ApiError) {
    if (exception.status === 429) return '操作过于频繁，请稍后再试'
    return exception.message
  }
  return '操作失败，请稍后重试'
}

function scopeLabel(scope: string): string {
  return scope === 'profile' ? '你的 RailLog 用户 ID、昵称和头像' : scope
}
</script>

<template>
  <div class="oauth-shell">
    <main class="oauth-card">
      <header class="oauth-brand">
        <img src="/raillog-icon.png" alt="" />
        <span>RailLog 轨记</span>
      </header>

      <div v-if="phase === 'loading'" class="oauth-state">
        <LoaderCircle class="spin" :size="28" />
        <p>正在校验授权请求…</p>
      </div>

      <div v-else-if="phase === 'invalid'" class="oauth-state">
        <LockKeyhole :size="28" />
        <h1>无法继续授权</h1>
        <p class="oauth-error">{{ error }}</p>
      </div>

      <div v-else-if="phase === 'login'" class="oauth-body">
        <h1>登录 RailLog 账户</h1>
        <p class="oauth-lead">
          <strong>{{ client?.name || '有应用' }}</strong>
          正在请求访问你的 RailLog 账户，请先登录以确认身份。
        </p>

        <form class="oauth-form" @submit.prevent="submitLogin">
          <label>
            <span>邮箱</span>
            <input
              v-model="email"
              type="email"
              autocomplete="username"
              placeholder="you@example.com"
              :disabled="submitting"
            />
          </label>
          <label>
            <span>密码</span>
            <div class="oauth-password">
              <input
                v-model="password"
                :type="showPassword ? 'text' : 'password'"
                autocomplete="current-password"
                placeholder="账户密码"
                :disabled="submitting"
              />
              <button
                type="button"
                class="oauth-reveal"
                :aria-label="showPassword ? '隐藏密码' : '显示密码'"
                @click="showPassword = !showPassword"
              >
                <EyeOff v-if="showPassword" :size="18" />
                <Eye v-else :size="18" />
              </button>
            </div>
          </label>
          <p v-if="error" class="oauth-error">{{ error }}</p>
          <button class="oauth-primary" type="submit" :disabled="submitting">
            <LoaderCircle v-if="submitting" class="spin" :size="18" />
            <span>{{ submitting ? '登录中…' : '登录并继续' }}</span>
          </button>
        </form>
      </div>

      <div v-else-if="phase === 'consent'" class="oauth-body">
        <h1>确认授权</h1>
        <div class="oauth-app">
          <img v-if="client?.logoUrl" :src="client.logoUrl" alt="" referrerpolicy="no-referrer" />
          <ShieldCheck v-else :size="32" />
          <div>
            <strong>{{ client?.name }}</strong>
            <span>请求访问你的 RailLog 账户</span>
          </div>
        </div>

        <p class="oauth-lead">授权后，该应用可以确认你的账户身份，并获得：</p>
        <ul class="oauth-scopes">
          <li v-for="scope in client?.scopes ?? []" :key="scope">
            <ShieldCheck :size="16" />
            <span>{{ scopeLabel(scope) }}</span>
          </li>
        </ul>
        <p class="oauth-note">
          当前登录账户：{{ displayName }}。授权只会确认身份，不会读取你的密码。
        </p>

        <p v-if="error" class="oauth-error">{{ error }}</p>
        <div class="oauth-actions">
          <button class="oauth-secondary" :disabled="submitting" @click="submitDecision(false)">
            <ArrowLeft :size="17" />
            <span>拒绝</span>
          </button>
          <button class="oauth-primary" :disabled="submitting" @click="submitDecision(true)">
            <LoaderCircle v-if="submitting" class="spin" :size="18" />
            <span>允许授权</span>
          </button>
        </div>
      </div>

      <div v-else class="oauth-state">
        <LoaderCircle class="spin" :size="28" />
        <p>正在返回万花筒…</p>
        <p class="oauth-note">如果没有自动跳转，请手动切回万花筒。</p>
      </div>
    </main>

    <footer class="oauth-footer">
      <a href="/">RailLog 轨记</a>
      <span>·</span>
      <a href="/api-docs/">开发者文档</a>
    </footer>
  </div>
</template>
