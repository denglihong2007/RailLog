<script setup lang="ts">
import { Download, KeyRound, LockKeyhole } from '@lucide/vue'
import { ref } from 'vue'

const props = defineProps<{ apiBase: string }>()
const keyValue = ref('')
const password = ref('')
const restrictionText = ref('限乘当日当次车')
const memorialText = ref('')
const noticeLine1 = ref('仅供收藏使用  严禁乘车或报销')
const noticeLine2 = ref('寻梦交通文创祝您旅途愉快')
const busy = ref(false)
const error = ref('')

async function downloadPdf() {
  const key = keyValue.value.trim()
  if (!key || !password.value) {
    error.value = '请输入下载密码和 Key'
    return
  }
  busy.value = true
  error.value = ''
  try {
    const response = await fetch(`${props.apiBase}/api/ticket-generator/web-pdf`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        key,
        password: password.value,
        restrictionText: restrictionText.value.trim(),
        memorialText: memorialText.value.trim(),
        noticeLine1: noticeLine1.value.trim(),
        noticeLine2: noticeLine2.value.trim(),
      }),
    })
    if (!response.ok) {
      const body = await response.json().catch(() => null) as { message?: string } | null
      throw new Error(body?.message ?? `下载失败（${response.status}）`)
    }
    const blob = await response.blob()
    const disposition = response.headers.get('content-disposition') ?? ''
    const match = disposition.match(/filename="?([^";]+)"?/i)
    const filename = match?.[1] ?? 'RailLog_车票排版.pdf'
    const url = URL.createObjectURL(blob)
    const anchor = document.createElement('a')
    anchor.href = url
    anchor.download = filename
    document.body.appendChild(anchor)
    anchor.click()
    anchor.remove()
    URL.revokeObjectURL(url)
  } catch (reason) {
    error.value = reason instanceof Error ? reason.message : '下载失败，请稍后重试'
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <section class="ticket-pdf-page" aria-labelledby="ticket-pdf-title">
    <form class="ticket-pdf-form" @submit.prevent="downloadPdf">
      <div class="ticket-pdf-heading">
        <Download :size="28" aria-hidden="true" />
        <div>
          <p>车票排版文件</p>
          <h1 id="ticket-pdf-title">PDF 下载</h1>
        </div>
      </div>

      <label for="pdf-password">下载密码</label>
      <div class="ticket-input">
        <LockKeyhole :size="20" aria-hidden="true" />
        <input id="pdf-password" v-model="password" type="password" autocomplete="current-password" required />
      </div>

      <label for="pdf-key">Key</label>
      <div class="ticket-input">
        <KeyRound :size="20" aria-hidden="true" />
        <input id="pdf-key" v-model="keyValue" type="text" inputmode="text" autocomplete="off" spellcheck="false" required />
      </div>

      <label for="restriction-text">提示文案</label>
      <div class="ticket-input">
        <input id="restriction-text" v-model="restrictionText" type="text" maxlength="40" />
      </div>

      <label for="memorial-text">防伪文案</label>
      <div class="ticket-input">
        <input id="memorial-text" v-model="memorialText" type="text" maxlength="40" />
      </div>

      <label for="notice-line-1">备注第一行</label>
      <div class="ticket-input">
        <input id="notice-line-1" v-model="noticeLine1" type="text" maxlength="40" />
      </div>

      <label for="notice-line-2">备注第二行</label>
      <div class="ticket-input">
        <input id="notice-line-2" v-model="noticeLine2" type="text" maxlength="40" />
      </div>

      <p v-if="error" class="ticket-pdf-error" role="alert">{{ error }}</p>
      <button type="submit" :disabled="busy">
        <Download :size="20" aria-hidden="true" />
        {{ busy ? '正在生成' : '下载 PDF' }}
      </button>
    </form>
  </section>
</template>

<style scoped>
.ticket-pdf-page { min-height:calc(100svh - 150px); padding:64px 20px; display:grid; place-items:center; background:var(--surface-low); }
.ticket-pdf-form { width:min(100%,460px); padding:28px; display:grid; gap:10px; border:1px solid var(--line); border-radius:8px; background:var(--surface); box-shadow:0 10px 30px color-mix(in srgb,var(--ink) 9%,transparent); }
.ticket-pdf-heading { display:flex; align-items:center; gap:14px; margin-bottom:12px; }
.ticket-pdf-heading>svg { color:var(--brand); }
.ticket-pdf-heading p { margin:0 0 2px; color:var(--muted); font-size:14px; }
.ticket-pdf-heading h1 { margin:0; display:block; font-size:30px; line-height:1.2; }
label { margin-top:8px; font-weight:700; }
.ticket-input { min-height:50px; padding:0 14px; display:flex; align-items:center; gap:10px; border:1px solid var(--line); border-radius:7px; background:var(--surface); }
.ticket-input:focus-within { border-color:var(--brand); outline:2px solid color-mix(in srgb,var(--brand) 22%,transparent); }
.ticket-input svg { flex:none; color:var(--muted); }
input { width:100%; min-width:0; border:0; outline:0; background:transparent; color:var(--ink); font:inherit; letter-spacing:0; }
.ticket-pdf-error { margin:8px 0 0; color:#b42318; line-height:1.5; }
button { min-height:50px; margin-top:12px; display:inline-flex; align-items:center; justify-content:center; gap:9px; border:0; border-radius:7px; background:var(--brand); color:#fff; font:inherit; font-weight:750; cursor:pointer; }
button:disabled { opacity:.62; cursor:wait; }
@media (max-width:520px) { .ticket-pdf-page { padding:28px 14px; align-items:start; } .ticket-pdf-form { padding:22px 18px; } }
@media (prefers-color-scheme:dark) { button { color:#5c0a05; } .ticket-pdf-error { color:#ffb4ab; } }
</style>
