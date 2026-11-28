import { describe, expect, it } from 'vitest'
import { selectorField, type SelectorField, type SourceKind } from './source-kinds'

describe('selectorField', () => {
  it.each<[SourceKind, SelectorField]>([
    [
      'slack',
      {
        kindLabel: 'Slack',
        label: 'Slack channel id',
        placeholder: 'C0123456789',
        hint: 'A public channel the happyhappy bot has joined.',
      },
    ],
    [
      'discord',
      {
        kindLabel: 'Discord',
        label: 'Discord channel id',
        placeholder: '1100000000000000001',
        hint: 'A channel in a server the happyhappy bot is invited to.',
      },
    ],
    [
      'intercom',
      {
        kindLabel: 'Intercom',
        label: 'Intercom inbox or team id',
        placeholder: '7000001',
        hint: 'New conversations and customer replies assigned to this inbox or team.',
      },
    ],
    [
      'email',
      {
        kindLabel: 'Email',
        label: 'Inbound address',
        placeholder: 'help@cora.computer',
        hint: 'The address Postmark forwards to happyhappy.',
      },
    ],
    [
      'x',
      {
        kindLabel: 'X',
        label: 'X search query',
        placeholder: '(@every OR @cora_computer) -is:retweet',
        hint: 'Keywords or mentions, searched every 15 minutes.',
      },
    ],
    [
      'custom',
      {
        kindLabel: 'Custom webhook',
        label: 'Webhook token',
        placeholder: '',
        hint: 'Generated when the source is created.',
      },
    ],
  ])('returns the field metadata for %s', (kind, expected) => {
    expect(selectorField(kind)).toEqual(expected)
  })

  it('throws on an unknown source kind', () => {
    expect(() => selectorField('sms' as SourceKind)).toThrow('Unknown source kind: sms')
  })
})
