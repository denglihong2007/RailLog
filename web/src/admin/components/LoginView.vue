<script setup lang="ts">
import { ref } from 'vue'
import {
  ArrowRight,
  Eye,
  EyeOff,
  KeyRound,
  LoaderCircle,
  Mail,
  Megaphone,
  ShieldCheck,
  TrainFront,
  Trophy,
  Users,
} from '@lucide/vue'
import { api, ApiError, type AdminSession } from '../api'

const emit = defineEmits<{ 'logged-in': [session: AdminSession] }>()

const email = ref('')
const password = ref('')
const showPassword = ref(false)
const submitting = ref(false)
const error = ref('')

async function submit(): Promise<void> {
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
    const session = await api.login(email.value.trim(), password.value)
    emit('logged-in', session)
  } catch (exception) {
    if (exception instanceof ApiError) {
      error.value =
        exception.status === 429
          ? '尝试次数过多，请稍后再试'
          : exception.status === 403
            ? '该账户没有管理员权限'
            : exception.message
    } else {
      error.value = '登录失败，请稍后重试'
    }
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <div class="login-page">
    <section class="login-brand-panel">
      <div class="login-brand">
        <img src="/raillog-icon.png" alt="" />
        <div>
          <strong>RailLog</strong>
          <span>管理后台</span>
        </div>
      </div>
      <div class="login-copy">
        <p class="login-eyebrow"><TrainFront :size="17" /> RailLog Operations</p>
        <h1>让每一段<br />铁路旅程<br /><em>都在掌控之中</em></h1>
        <p class="login-lead">
          集中维护主页公告、处理用户行程数据、查看全站排行榜。
          所有修改会在用户下次同步时送达客户端。
        </p>
        <ul class="login-features">
          <li><Megaphone :size="18" /><span><strong>公告管理</strong>即时上下线主页轮播公告</span></li>
          <li><Users :size="18" /><span><strong>行程编辑</strong>检索用户，修正或补录行程</span></li>
          <li><Trophy :size="18" /><span><strong>排行榜</strong>用户、行程与线路要素排名</span></li>
        </ul>
      </div>
      <p class="login-panel-foot">仅限授权管理员访问 · 操作会被记录在服务端日志中</p>
    </section>

    <section class="login-form-panel">
      <form class="login-card" @submit.prevent="submit">
        <div class="login-card-head">
          <span class="login-card-icon"><ShieldCheck :size="26" /></span>
          <h2>管理员登录</h2>
          <p>使用拥有管理员权限的 RailLog 账户登录</p>
        </div>

        <label class="field">
          <span class="field-label">账户邮箱</span>
          <span class="input-with-icon">
            <Mail :size="18" />
            <input
              v-model="email"
              type="email"
              autocomplete="username"
              placeholder="name@example.com"
              autofocus
            />
          </span>
        </label>

        <label class="field">
          <span class="field-label">密码</span>
          <span class="input-with-icon">
            <KeyRound :size="18" />
            <input
              v-model="password"
              :type="showPassword ? 'text' : 'password'"
              autocomplete="current-password"
              placeholder="输入账户密码"
            />
            <button
              type="button"
              class="input-icon-button"
              :aria-label="showPassword ? '隐藏密码' : '显示密码'"
              @click="showPassword = !showPassword"
            >
              <EyeOff v-if="showPassword" :size="17" />
              <Eye v-else :size="17" />
            </button>
          </span>
        </label>

        <p v-if="error" class="form-error" role="alert">{{ error }}</p>

        <button type="submit" class="button primary large full" :disabled="submitting">
          <LoaderCircle v-if="submitting" :size="18" class="spin" />
          <template v-else>登录后台 <ArrowRight :size="18" /></template>
        </button>

        <p class="login-hint">
          管理员权限由服务端的账户 ID 白名单决定，仍使用 RailLog 账户密码登录。
        </p>
      </form>
    </section>
  </div>
</template>
