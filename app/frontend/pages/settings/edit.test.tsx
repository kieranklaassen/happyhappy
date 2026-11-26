import { router } from '@inertiajs/react'
import { act, fireEvent, render, screen } from '@testing-library/react'
import { type ComponentProps, type ReactNode } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import SettingsEdit from './edit'

// useForm stays real, so dirty state, the transform and error handling are the ones the page ships with.
vi.mock('@inertiajs/react', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@inertiajs/react')>()),
  Head: () => null,
  usePage: () => ({ url: '/settings', props: { flash: {} } }),
  Link: ({ href, children }: { href: string; children: ReactNode }) => <a href={href}>{children}</a>,
}))

type Setting = ComponentProps<typeof SettingsEdit>['setting']

const setting: Setting = {
  low_confidence_threshold: 0.55,
  escalation_threshold: 0.8,
  report_back_window_minutes: 90,
  anomaly_sensitivity: 2.5,
  anomaly_min_count: 11,
  anomaly_min_baseline_windows: 12,
  anomaly_active_days: 13,
  team_email_domains: ['every.to', 'example.com'],
  team_discord_role_ids: ['21', '22'],
  team_discord_user_ids: [],
  slack_channel_id: null,
  digest_time_zone: 'Europe/Amsterdam',
  digest_hour: 9,
  incident_window_minutes: 45,
  slack_interactivity: false,
}

const submittedSetting = {
  low_confidence_threshold: '0.55',
  escalation_threshold: '0.8',
  report_back_window_minutes: '90',
  anomaly_sensitivity: '2.5',
  anomaly_min_count: '11',
  anomaly_min_baseline_windows: '12',
  anomaly_active_days: '13',
  team_email_domains: 'every.to, example.com',
  team_discord_role_ids: '21, 22',
  team_discord_user_ids: '',
  slack_channel_id: '',
  digest_time_zone: 'Europe/Amsterdam',
  digest_hour: '9',
  incident_window_minutes: '45',
  slack_interactivity: false,
}

const ratio = { type: 'number', min: '0', max: '1', step: '0.01', required: true }
const whole = { type: 'number', min: '1', max: '', step: '1', required: true }
const text = { type: 'text', min: '', max: '', step: '', required: false }

// Every field in the order it appears, with the start of its hint.
const FIELDS = [
  { name: 'low_confidence_threshold', label: 'Low-confidence threshold', hint: 'Labels with a probability', attributes: ratio },
  { name: 'escalation_threshold', label: 'Default escalation threshold', hint: 'Anger probability', attributes: ratio },
  { name: 'report_back_window_minutes', label: 'Report-back window (minutes)', hint: 'A claimed item', attributes: whole },
  {
    name: 'anomaly_sensitivity',
    label: 'Anomaly sensitivity',
    hint: 'How many standard deviations',
    attributes: { ...whole, min: '0.1', step: '0.1' },
  },
  { name: 'anomaly_min_count', label: 'Minimum messages per window', hint: 'Windows with fewer', attributes: whole },
  { name: 'anomaly_min_baseline_windows', label: 'Minimum baseline windows', hint: 'How many earlier', attributes: whole },
  { name: 'anomaly_active_days', label: 'Active window (days)', hint: 'Anomalies older', attributes: whole },
  { name: 'slack_channel_id', label: 'Slack channel', hint: 'Channel ID', attributes: text },
  { name: 'incident_window_minutes', label: 'Incident window (minutes)', hint: 'Bad-news anomalies', attributes: whole },
  { name: 'slack_interactivity', label: 'Slack interactivity', hint: 'Turn on once' },
  { name: 'digest_time_zone', label: 'Daily overview time zone', hint: 'The overview covers' },
  { name: 'digest_hour', label: 'Daily overview time', hint: 'When the overview posts' },
  { name: 'team_email_domains', label: 'Team email domains', hint: 'Messages from these', attributes: text },
  { name: 'team_discord_role_ids', label: 'Team Discord role IDs', hint: 'Discord members', attributes: text },
  { name: 'team_discord_user_ids', label: 'Team Discord user IDs', hint: 'Discord users', attributes: text },
] as const

function control(name: string) {
  return document.getElementById(`setting_${name}`) as HTMLInputElement | HTMLSelectElement
}

function renderPage() {
  return render(<SettingsEdit setting={setting} time_zones={['UTC', 'Europe/Amsterdam']} />)
}

function saveButton() {
  return screen.getByRole('button', { name: 'Save settings' })
}

describe('Settings page', () => {
  const patch = vi.spyOn(router, 'patch').mockImplementation(() => {})

  beforeEach(() => {
    patch.mockClear()
  })

  it('renders every field in order with its label and hint', () => {
    const { container } = renderPage()

    const controls = Array.from(container.querySelectorAll('form input, form select'))
    expect(controls.map((element) => element.id)).toEqual(FIELDS.map((field) => `setting_${field.name}`))

    FIELDS.forEach((field) => {
      const label = container.querySelector(`label[for="setting_${field.name}"]`)
      expect(label).toHaveTextContent(field.label)
      expect(label?.parentElement?.querySelector('p')?.textContent).toMatch(new RegExp(`^${field.hint}`))
    })
  })

  it.each(FIELDS.flatMap((field) => ('attributes' in field ? [field] : [])))(
    'limits what $name accepts',
    ({ name, attributes }) => {
      renderPage()

      const { type, min, max, step, required } = control(name) as HTMLInputElement
      expect({ type, min, max, step, required }).toEqual(attributes)
    },
  )

  it('asks for commas between the entries of a team list', () => {
    renderPage()

    expect(screen.getAllByText(/Separate entries with commas\.$/)).toHaveLength(3)
  })

  it('offers the given time zones and every hour of the day', () => {
    renderPage()

    const labels = (name: string) => Array.from(control(name).querySelectorAll('option')).map((option) => option.text)
    expect(labels('digest_time_zone')).toEqual(['UTC', 'Europe/Amsterdam'])
    expect(labels('digest_hour')).toEqual(
      Array.from({ length: 24 }, (_, hour) => (hour < 10 ? `0${hour}:00` : `${hour}:00`)),
    )
  })

  it('shows the stored values', () => {
    renderPage()

    Object.entries(submittedSetting).forEach(([name, value]) => {
      const element = control(name)
      if (typeof value === 'boolean') expect((element as HTMLInputElement).checked).toBe(value)
      else expect(element.value).toBe(value)
    })
  })

  it('cannot be saved until something changes', () => {
    renderPage()
    expect(saveButton()).toBeDisabled()

    fireEvent.change(control('slack_channel_id'), { target: { value: 'C1' } })

    expect(saveButton()).toBeEnabled()
  })

  it('patches the stored values under setting', () => {
    renderPage()

    fireEvent.submit(saveButton().closest('form')!)

    expect(patch).toHaveBeenCalledExactlyOnceWith('/settings', { setting: submittedSetting }, expect.any(Object))
  })

  it.each([
    ...FIELDS.flatMap((field) =>
      'attributes' in field ? [{ name: field.name, value: field.attributes.type === 'number' ? '0.5' : 'changed' }] : [],
    ),
    { name: 'digest_time_zone', value: 'UTC' },
    { name: 'digest_hour', value: '17' },
  ])('submits an edited $name and leaves the rest alone', ({ name, value }) => {
    renderPage()

    fireEvent.change(control(name), { target: { value } })
    fireEvent.submit(saveButton().closest('form')!)

    expect(control(name)).toHaveValue(control(name).getAttribute('type') === 'number' ? Number(value) : value)
    expect(patch.mock.calls[0][1]).toEqual({ setting: { ...submittedSetting, [name]: value } })
  })

  it('submits the Slack interactivity checkbox as a boolean', () => {
    renderPage()

    fireEvent.click(screen.getByLabelText('Resolve incidents from Slack buttons'))
    fireEvent.submit(saveButton().closest('form')!)

    expect(patch.mock.calls[0][1]).toEqual({ setting: { ...submittedSetting, slack_interactivity: true } })
  })

  it('shows each field its own validation error', () => {
    renderPage()
    fireEvent.submit(saveButton().closest('form')!)
    const options = patch.mock.calls[0][2]!

    const errors = Object.fromEntries(FIELDS.map(({ name }) => [name, [`rejects ${name}`]]))
    act(() => {
      // Rails sends a list of messages per field.
      void options.onError?.(errors as never)
    })

    expect(screen.getAllByRole('alert').map((alert) => alert.textContent)).toEqual(
      FIELDS.map(({ name, label }) => `${label} rejects ${name}`),
    )
  })

  // Saves, with the request still open until the returned function says it succeeded.
  function startSave() {
    fireEvent.submit(saveButton().closest('form')!)
    const options = patch.mock.lastCall![2]!
    act(() => void options.onStart?.({} as never))
    return async () => {
      await act(async () => void (await options.onSuccess?.({} as never)))
      act(() => void options.onFinish?.({} as never))
    }
  }

  it('has nothing left to save once a save succeeds', async () => {
    renderPage()
    fireEvent.change(control('slack_channel_id'), { target: { value: 'C1' } })

    const succeed = startSave()
    await succeed()

    expect(control('slack_channel_id')).toHaveValue('C1')
    expect(saveButton()).toBeDisabled()
  })

  it.each([
    { name: 'the saved field', field: 'slack_channel_id', value: 'C2' },
    { name: 'another field', field: 'team_email_domains', value: 'every.to' },
    { name: 'the saved field, back to its old value', field: 'slack_channel_id', value: '' },
  ])('keeps text typed into $name during a save ready for the next save', async ({ field, value }) => {
    renderPage()
    fireEvent.change(control('slack_channel_id'), { target: { value: 'C1' } })

    const succeed = startSave()
    fireEvent.change(control(field), { target: { value } })
    await succeed()

    expect(control(field)).toHaveValue(value)
    expect(saveButton()).toBeEnabled()
    const succeedAgain = startSave()
    expect(patch.mock.calls[1][1]).toEqual({ setting: { ...submittedSetting, slack_channel_id: 'C1', [field]: value } })
    await succeedAgain()
    expect(saveButton()).toBeDisabled()
  })
})
