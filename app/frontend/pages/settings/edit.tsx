import { Head, useForm } from '@inertiajs/react'
import { type FormEvent } from 'react'
import AppNav from '../../components/app-nav'
import { Field, FlashNotice, inputClass, primaryButtonClass } from '../../components/form-field'

interface SettingsEditProps {
  setting: {
    low_confidence_threshold: number
    escalation_threshold: number
    report_back_window_minutes: number
    team_email_domains: string[]
    team_discord_role_ids: string[]
    team_discord_user_ids: string[]
  }
}

const TEAM_LISTS = [
  {
    name: 'team_email_domains',
    label: 'Team email domains',
    hint: 'Messages from these email domains are written by Every’s team and never count toward moods.',
  },
  {
    name: 'team_discord_role_ids',
    label: 'Team Discord role IDs',
    hint: 'Discord members holding any of these server roles are Every’s team.',
  },
  {
    name: 'team_discord_user_ids',
    label: 'Team Discord user IDs',
    hint: 'Discord users who are Every’s team even without a team role.',
  },
] as const

export default function SettingsEdit({ setting }: SettingsEditProps) {
  const form = useForm({
    low_confidence_threshold: setting.low_confidence_threshold.toString(),
    escalation_threshold: setting.escalation_threshold.toString(),
    report_back_window_minutes: setting.report_back_window_minutes.toString(),
    team_email_domains: setting.team_email_domains.join(', '),
    team_discord_role_ids: setting.team_discord_role_ids.join(', '),
    team_discord_user_ids: setting.team_discord_user_ids.join(', '),
  })

  function submit(event: FormEvent) {
    event.preventDefault()
    form.transform((data) => ({ setting: data }))
    form.patch('/settings', { onSuccess: () => form.setDefaults() })
  }

  return (
    <>
      <Head title="Settings" />
      <AppNav />
      <main className="mx-auto flex max-w-2xl flex-col gap-6 px-6 py-8">
        <h1 className="text-2xl font-bold tracking-tight text-gray-900">Settings</h1>
        <FlashNotice />

        <form onSubmit={submit} className="flex flex-col gap-5">
          <Field
            label="Low-confidence threshold"
            htmlFor="setting_low_confidence_threshold"
            error={form.errors.low_confidence_threshold}
            hint="Labels with a probability below this, from 0 to 1, are flagged for human review."
          >
            <input
              id="setting_low_confidence_threshold"
              type="number"
              min={0}
              max={1}
              step={0.01}
              required
              value={form.data.low_confidence_threshold}
              onChange={(e) => form.setData('low_confidence_threshold', e.target.value)}
              className={inputClass}
            />
          </Field>

          <Field
            label="Default escalation threshold"
            htmlFor="setting_escalation_threshold"
            error={form.errors.escalation_threshold}
            hint="Anger probability, from 0 to 1, that posts an escalation to Slack. Products can override it."
          >
            <input
              id="setting_escalation_threshold"
              type="number"
              min={0}
              max={1}
              step={0.01}
              required
              value={form.data.escalation_threshold}
              onChange={(e) => form.setData('escalation_threshold', e.target.value)}
              className={inputClass}
            />
          </Field>

          <Field
            label="Report-back window (minutes)"
            htmlFor="setting_report_back_window_minutes"
            error={form.errors.report_back_window_minutes}
            hint="A claimed item with no agent report for longer than this is flagged overdue."
          >
            <input
              id="setting_report_back_window_minutes"
              type="number"
              min={1}
              step={1}
              required
              value={form.data.report_back_window_minutes}
              onChange={(e) => form.setData('report_back_window_minutes', e.target.value)}
              className={inputClass}
            />
          </Field>

          {TEAM_LISTS.map((list) => (
            <Field
              key={list.name}
              label={list.label}
              htmlFor={`setting_${list.name}`}
              error={form.errors[list.name]}
              hint={`${list.hint} Separate entries with commas.`}
            >
              <input
                id={`setting_${list.name}`}
                type="text"
                value={form.data[list.name]}
                onChange={(e) => form.setData(list.name, e.target.value)}
                className={inputClass}
              />
            </Field>
          ))}

          <div>
            <button type="submit" disabled={form.processing || !form.isDirty} className={primaryButtonClass}>
              Save settings
            </button>
          </div>
        </form>
      </main>
    </>
  )
}
