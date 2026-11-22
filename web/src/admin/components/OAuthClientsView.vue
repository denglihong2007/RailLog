<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import {
  Copy,
  KeyRound,
  LoaderCircle,
  Plus,
  ShieldAlert,
  ShieldCheck,
  TriangleAlert,
  X,
} from '@lucide/vue'
import {
  api,
  ApiError,
  type CreateOAuthClientResult,
  type OAuthClientSummary,
} from '../api'
import { confirmDestructive } from '../confirm'
import { formatDate } from '../format'
import { toast } from '../toast'

const clients = ref<OAuthClientSummary[]>([])
const loading = ref(true)
const error = ref('')
const saving = ref(false)
const revoking = ref<string | null>(null)
const showEditor = ref(false)
const created = ref<CreateOAuthClientResult | null>(null)

const form = reactive({
  name: '',
  logoUrl: '',
  redirectUris: '',
})

async function load(): Promise<void> {
  loading.value = true
  error.value = ''
  try {
    clients.value = await api.oauthClients()
  } catch (exception) {
    error.value = exception instanceof ApiError ? exception.message : '读取合作应用失败'
  } finally {
    loading.value = false
  }
}

function openCreate(): void {
  form.name = ''
  form.logoUrl = ''
  form.redirectUris = ''
  showEditor.value = true
}

function closeEditor(): void {
  if (saving.value) return
  showEditor.value = false
}

async function submit(): Promise<void> {
  if (saving.value) return
  const name = form.name.trim()
  const redirectUris = form.redirectUris
    .split('\n')
    .map((item) => item.trim())
    .filter(Boolean)
  if (!name) {
    toast('应用名称不能为空', 'error')
    return
  }
  if (redirectUris.length === 0) {
    toast('至少填写一个回调地址', 'error')
    return
  }
  saving.value = true
  try {
    created.value = await api.createOAuthClient({
      name,
      logoUrl: form.logoUrl.trim() || null,
      redirectUris,
      scopes: ['profile'],
    })
    showEditor.value = false
    await load()
    toast('应用已登记', 'success')
  } catch (exception) {
    toast(exception instanceof ApiError ? exception.message : '登记失败', 'error')
  } finally {
    saving.value = false
  }
}

async function revoke(item: OAuthClientSummary): Promise<void> {
  if (revoking.value) return
  const confirmed = confirmDestructive({
    title: `停用「${item.name}」？`,
    message:
      '该应用名下的全部授权令牌会立即失效，已绑定的用户需要重新授权；应用本身会保留，可以重新登记一个新应用。',
  })
  if (!confirmed) return
  revoking.value = item.clientId
  try {
    await api.revokeOAuthClient(item.clientId)
    toast('应用已停用', 'info')
    await load()
  } catch (exception) {
    toast(exception instanceof ApiError ? exception.message : '停用失败', 'error')
  } finally {
    revoking.value = null
  }
}

async function copy(label: string, value: string): Promise<void> {
  try {
    await navigator.clipboard.writeText(value)
    toast(`${label}已复制`, 'info')
  } catch {
    toast('复制失败，请手动选中复制', 'error')
  }
}

onMounted(load)
</script>

<template>
  <div class="page-stack">
    <section class="panel">
      <div class="panel-head">
        <div>
          <h2>合作应用</h2>
          <p>
            第三方应用通过 OAuth 2.0 确认用户身份。登记时生成的
            <code>client_secret</code> 只显示一次，请立刻保存并通过安全渠道交付。
          </p>
        </div>
        <button type="button" class="button primary" @click="openCreate">
          <Plus :size="17" /> 登记应用
        </button>
      </div>

      <div v-if="loading" class="state-card inline">
        <LoaderCircle :size="20" class="spin" /><span>正在读取合作应用…</span>
      </div>
      <div v-else-if="error" class="state-card inline error">
        <TriangleAlert :size="20" /><span>{{ error }}</span>
      </div>

      <div v-else-if="clients.length === 0" class="empty-state">
        <span class="empty-icon"><KeyRound :size="30" /></span>
        <h3>还没有合作应用</h3>
        <p>登记后即可把 client_id 和 client_secret 交给对方接入。</p>
        <button type="button" class="button primary" @click="openCreate">
          <Plus :size="17" /> 登记应用
        </button>
      </div>

      <div v-else class="table-wrap">
        <table class="data-table">
          <thead>
            <tr>
              <th>应用</th>
              <th>client_id</th>
              <th>回调地址</th>
              <th>权限</th>
              <th>状态</th>
              <th>登记时间</th>
              <th>操作</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="item in clients"
              :key="item.clientId"
              :class="{ muted: item.revokedAt }"
            >
              <td>
                <div class="partner-cell">
                  <img
                    v-if="item.logoUrl"
                    class="partner-logo"
                    :src="item.logoUrl"
                    alt=""
                    referrerpolicy="no-referrer"
                  />
                  <span v-else class="partner-logo placeholder">
                    <ShieldCheck :size="16" />
                  </span>
                  <strong>{{ item.name }}</strong>
                </div>
              </td>
              <td><code>{{ item.clientId }}</code></td>
              <td>
                <div class="redirect-list">
                  <code v-for="uri in item.redirectUris" :key="uri">{{ uri }}</code>
                </div>
              </td>
              <td>
                <span v-for="scope in item.scopes" :key="scope" class="pill neutral">
                  {{ scope }}
                </span>
              </td>
              <td>
                <span :class="['pill', item.revokedAt ? 'neutral' : 'success']">
                  {{ item.revokedAt ? '已停用' : '正常' }}
                </span>
              </td>
              <td>{{ formatDate(item.createdAt) }}</td>
              <td>
                <button
                  v-if="!item.revokedAt"
                  type="button"
                  class="button danger"
                  :disabled="revoking === item.clientId"
                  @click="revoke(item)"
                >
                  <LoaderCircle
                    v-if="revoking === item.clientId"
                    :size="15"
                    class="spin"
                  />
                  停用
                </button>
                <span v-else class="muted">—</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <Teleport to="body">
      <div v-if="showEditor" class="modal-backdrop" @click.self="closeEditor">
        <div
          class="modal narrow"
          role="dialog"
          aria-modal="true"
          aria-labelledby="oauth-client-editor-title"
        >
          <header class="modal-head">
            <div>
              <h2 id="oauth-client-editor-title">登记合作应用</h2>
              <p>回调地址必须与对方实际使用的一致，不做前缀或通配匹配</p>
            </div>
            <button type="button" class="icon-button" aria-label="关闭" @click="closeEditor">
              <X :size="19" />
            </button>
          </header>

          <div class="modal-body">
            <label class="field">
              <span class="field-label">应用名称 <em>*</em></span>
              <input v-model="form.name" maxlength="80" placeholder="例如：万花筒 RailKale" />
            </label>
            <label class="field">
              <span class="field-label">图标 URL</span>
              <input
                v-model="form.logoUrl"
                type="url"
                placeholder="https://www.raillog.top/partners/example.png"
              />
              <span class="field-hint">
                建议托管在 RailLog 自己的域名下，避免授权页外链对方服务器。
              </span>
            </label>
            <label class="field">
              <span class="field-label">回调地址 <em>*</em></span>
              <textarea
                v-model="form.redirectUris"
                rows="3"
                placeholder="railkale://oauth/callback"
              />
              <span class="field-hint">每行一个，必须与对方实际使用的一致。</span>
            </label>
            <div class="field">
              <span class="field-label">权限</span>
              <div><span class="pill neutral">profile</span></div>
              <span class="field-hint">
                目前只开放 profile：用户 ID、昵称和头像。行程数据仍走公开接口。
              </span>
            </div>
          </div>

          <footer class="modal-foot">
            <button type="button" class="button ghost" :disabled="saving" @click="closeEditor">
              取消
            </button>
            <button type="button" class="button primary" :disabled="saving" @click="submit">
              <LoaderCircle v-if="saving" :size="17" class="spin" />
              <Plus v-else :size="17" />
              登记
            </button>
          </footer>
        </div>
      </div>
    </Teleport>

    <Teleport to="body">
      <div v-if="created" class="modal-backdrop">
        <div
          class="modal narrow"
          role="dialog"
          aria-modal="true"
          aria-labelledby="oauth-secret-title"
        >
          <header class="modal-head">
            <div>
              <h2 id="oauth-secret-title">凭证只显示这一次</h2>
              <p>关闭后无法再次查看 client_secret，只能停用后重新登记</p>
            </div>
          </header>

          <div class="modal-body">
            <div class="secret-row">
              <span class="field-label">client_id</span>
              <div class="secret-value">
                <code>{{ created.clientId }}</code>
                <button
                  type="button"
                  class="icon-button"
                  aria-label="复制 client_id"
                  @click="copy('client_id', created.clientId)"
                >
                  <Copy :size="16" />
                </button>
              </div>
            </div>
            <div class="secret-row">
              <span class="field-label">client_secret</span>
              <div class="secret-value">
                <code>{{ created.clientSecret }}</code>
                <button
                  type="button"
                  class="icon-button"
                  aria-label="复制 client_secret"
                  @click="copy('client_secret', created.clientSecret)"
                >
                  <Copy :size="16" />
                </button>
              </div>
            </div>
            <div class="state-card inline error">
              <ShieldAlert :size="18" />
              <span>不要通过公开渠道发送 client_secret，也不要把 secret 打进客户端安装包。</span>
            </div>
          </div>

          <footer class="modal-foot">
            <button type="button" class="button primary" @click="created = null">
              我已保存
            </button>
          </footer>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<style scoped>
.partner-cell {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 140px;
}

.partner-logo {
  width: 24px;
  height: 24px;
  border-radius: 6px;
  object-fit: cover;
  flex: none;
}

.partner-logo.placeholder {
  display: grid;
  place-items: center;
  background: var(--field, #f1edeb);
  color: var(--faint, #8a7f7b);
}

.redirect-list {
  display: flex;
  flex-direction: column;
  gap: 3px;
  font-size: 12px;
  word-break: break-all;
}

.secret-row {
  display: grid;
  gap: 6px;
  margin-bottom: 14px;
}

.secret-value {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 8px 10px;
  border: 1px solid var(--line, #e4dedb);
  border-radius: 9px;
  background: var(--surface, #fff);
}

.secret-value code {
  flex: 1;
  font-size: 12px;
  word-break: break-all;
}
</style>
