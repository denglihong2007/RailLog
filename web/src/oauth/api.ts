const API_BASE = (import.meta.env.VITE_API_URL ?? '').replace(/\/$/, '')

export interface AuthorizeParams {
  clientId: string
  redirectUri: string
  responseType: string
  scope: string
  state: string
  codeChallenge: string
  codeChallengeMethod: string
}

export interface AuthorizeClient {
  clientId: string
  name: string
  logoUrl: string | null
  scopes: string[]
}

export class ApiError extends Error {
  status: number
  code: string

  constructor(status: number, code: string, message: string) {
    super(message)
    this.status = status
    this.code = code
  }
}

export function readAuthorizeParams(search: string): AuthorizeParams | null {
  const query = new URLSearchParams(search)
  const params: AuthorizeParams = {
    clientId: query.get('client_id')?.trim() ?? '',
    redirectUri: query.get('redirect_uri')?.trim() ?? '',
    responseType: query.get('response_type')?.trim() || 'code',
    scope: query.get('scope')?.trim() || 'profile',
    state: query.get('state') ?? '',
    codeChallenge: query.get('code_challenge')?.trim() ?? '',
    codeChallengeMethod: query.get('code_challenge_method')?.trim() || 'S256',
  }
  if (
    !params.clientId ||
    !params.redirectUri ||
    !params.state ||
    !params.codeChallenge
  ) {
    return null
  }
  return params
}

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  let response: Response
  try {
    response = await fetch(`${API_BASE}${path}`, {
      ...init,
      headers: {
        Accept: 'application/json',
        ...(init.headers ?? {}),
      },
    })
  } catch {
    throw new ApiError(0, 'network_error', '网络连接失败，请稍后重试')
  }

  const text = await response.text()
  let data: unknown = null
  if (text) {
    try {
      data = JSON.parse(text)
    } catch {
      data = null
    }
  }
  const payload = data as
    | {
        error?: string
        errorDescription?: string
        error_description?: string
        message?: string
      }
    | null
  if (!response.ok) {
    throw new ApiError(
      response.status,
      payload?.error ?? '',
      payload?.errorDescription ??
        payload?.error_description ??
        payload?.message ??
        '请求失败',
    )
  }
  return data as T
}

export function fetchClient(params: AuthorizeParams): Promise<AuthorizeClient> {
  const query = new URLSearchParams({
    client_id: params.clientId,
    redirect_uri: params.redirectUri,
    response_type: params.responseType,
    scope: params.scope,
    state: params.state,
    code_challenge: params.codeChallenge,
    code_challenge_method: params.codeChallengeMethod,
  })
  return request<AuthorizeClient>(`/api/oauth/authorize?${query.toString()}`)
}

export async function login(
  email: string,
  password: string,
): Promise<{ token: string; displayName: string }> {
  const data = await request<{
    token: string
    user: { displayName: string }
  }>('/api/auth/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  })
  return { token: data.token, displayName: data.user.displayName }
}

export function decide(
  params: AuthorizeParams,
  token: string,
  approved: boolean,
): Promise<string> {
  return request<{ redirectUrl: string }>('/api/oauth/authorize/decision', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({
      clientId: params.clientId,
      redirectUri: params.redirectUri,
      scope: params.scope,
      state: params.state,
      codeChallenge: params.codeChallenge,
      codeChallengeMethod: params.codeChallengeMethod,
      approved,
    }),
  }).then((data) => data.redirectUrl)
}
