import { toast } from './toast'

/**
 * 后台破坏性操作的统一确认。
 *
 * 所有会删除数据、撤销凭据或覆盖配置的操作都走这里，保证文案一致地
 * 说明「做什么」和「无法撤销」，避免有的页面只问「确定吗」。
 */

export interface DestructiveConfirmOptions {
  title: string
  message: string
  /** 可恢复的操作（如软删除行程）传 false，确认框会说明如何恢复。 */
  reversible?: boolean
  /** 自定义尾部提示，优先级高于 reversible。 */
  footnote?: string
}

const IRREVERSIBLE_NOTE = '此操作无法撤销，请确认后再继续。'
const REVERSIBLE_NOTE = '这是可恢复的操作，删除后仍能还原。'

/** 普通破坏性操作：一段说明 + 是否可撤销的提示。 */
export function confirmDestructive(options: DestructiveConfirmOptions): boolean {
  const footnote =
    options.footnote ?? (options.reversible ? REVERSIBLE_NOTE : IRREVERSIBLE_NOTE)
  return window.confirm([options.title, '', options.message, '', footnote].join('\n'))
}

export interface TypedConfirmOptions extends DestructiveConfirmOptions {
  /** 用户必须原样输入的文本，通常是昵称或文件名。 */
  expected: string
}

/** 高危操作：要求输入目标名称，防止误点。 */
export function confirmByTyping(options: TypedConfirmOptions): boolean {
  const typed = window.prompt(
    [
      options.title,
      '',
      options.message,
      '',
      '此操作无法撤销。',
      `请输入「${options.expected}」以确认：`,
    ].join('\n'),
  )
  if (typed === null) return false
  if (typed.trim() !== options.expected) {
    toast('输入不匹配，已取消操作', 'error')
    return false
  }
  return true
}
