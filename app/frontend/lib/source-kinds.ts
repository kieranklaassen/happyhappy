export type SourceKind = 'slack' | 'discord' | 'intercom' | 'email' | 'x' | 'custom'

export interface SelectorField {
  kindLabel: string
  label: string
  placeholder: string
  hint: string
}

export function selectorField(kind: SourceKind): SelectorField {
  switch (kind) {
    case 'slack':
      return {
        kindLabel: 'Slack',
        label: 'Slack channel id',
        placeholder: 'C0123456789',
        hint: 'A public channel the happyhappy bot has joined.',
      }
    case 'discord':
      return {
        kindLabel: 'Discord',
        label: 'Discord channel id',
        placeholder: '1100000000000000001',
        hint: 'A channel in a server the happyhappy bot is invited to.',
      }
    case 'intercom':
      return {
        kindLabel: 'Intercom',
        label: 'Intercom inbox or team id',
        placeholder: '7000001',
        hint: 'New conversations and customer replies assigned to this inbox or team.',
      }
    case 'email':
      return {
        kindLabel: 'Email',
        label: 'Inbound address',
        placeholder: 'help@cora.computer',
        hint: 'The address Postmark forwards to happyhappy.',
      }
    case 'x':
      return {
        kindLabel: 'X',
        label: 'X search query',
        placeholder: '(@every OR @cora_computer) -is:retweet',
        hint: 'Keywords or mentions, searched every 15 minutes.',
      }
    case 'custom':
      return {
        kindLabel: 'Custom webhook',
        label: 'Webhook token',
        placeholder: '',
        hint: 'Generated when the source is created.',
      }
    default: {
      const unhandled: never = kind
      throw new Error(`Unknown source kind: ${String(unhandled)}`)
    }
  }
}
