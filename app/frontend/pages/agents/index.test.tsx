import { fireEvent, render, screen } from '@testing-library/react'
import { type ReactNode } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import AgentsIndex, { type AgentRow } from './index'

const post = vi.fn()
const patch = vi.fn()
const form = {
  data: { name: '' },
  errors: {} as Record<string, string>,
  setData: vi.fn(),
  post,
  reset: vi.fn(),
  processing: false,
}

vi.mock('@inertiajs/react', () => ({
  Head: () => null,
  usePage: () => ({ url: '/agents', props: { flash: {} } }),
  useForm: () => form,
  router: { patch: (...args: unknown[]) => patch(...args) },
  Link: ({ href, children }: { href: string; children: ReactNode }) => <a href={href}>{children}</a>,
}))

const agents: AgentRow[] = [
  {
    id: 1,
    name: 'Cursor',
    created_at: '2026-09-24T10:00:00Z',
    last_used_at: '2026-09-24T11:00:00Z',
    revoked_at: null,
    claimed_count: 2,
  },
  {
    id: 2,
    name: 'Retired bot',
    created_at: '2026-09-20T10:00:00Z',
    last_used_at: null,
    revoked_at: '2026-09-23T10:00:00Z',
    claimed_count: 0,
  },
]

describe('Agents page', () => {
  beforeEach(() => {
    post.mockClear()
    patch.mockClear()
    form.errors = {}
  })

  it('lists agents with their status and offers revoke only for active ones', () => {
    render(<AgentsIndex agents={agents} new_token={null} />)

    expect(screen.getByText('Cursor')).toBeInTheDocument()
    expect(screen.getByText('Active')).toBeInTheDocument()
    expect(screen.getByText(/^Revoked /)).toBeInTheDocument()
    expect(screen.getAllByRole('button', { name: 'Revoke' })).toHaveLength(1)
  })

  it('shows a new token once, with a warning that it cannot be recovered', () => {
    render(
      <AgentsIndex agents={agents} new_token={{ agent_id: 1, name: 'Cursor', token: 'hh_secret123' }} />,
    )

    expect(screen.getByTestId('new-token')).toHaveTextContent('hh_secret123')
    expect(screen.getByText(/shown only once/i)).toBeInTheDocument()
  })

  it('shows no token section when there is no new token', () => {
    render(<AgentsIndex agents={agents} new_token={null} />)

    expect(screen.queryByTestId('new-token')).not.toBeInTheDocument()
  })

  it('posts the new agent name to /agents', () => {
    render(<AgentsIndex agents={[]} new_token={null} />)

    const submitted = fireEvent.submit(screen.getByRole('button', { name: /issue token/i }).closest('form')!)

    expect(post).toHaveBeenCalledWith('/agents', expect.any(Object))
    expect(submitted).toBe(false)
  })

  it('surfaces a name error from the server', () => {
    form.errors = { name: 'Name has already been taken' }
    render(<AgentsIndex agents={[]} new_token={null} />)

    expect(screen.getByRole('alert')).toHaveTextContent('Name has already been taken')
  })

  it('explains that WebMCP uses your browser session', () => {
    render(<AgentsIndex agents={agents} new_token={null} />)

    const section = screen.getByRole('region', { name: 'WebMCP in your browser' })
    expect(section).toHaveTextContent(/act with your browser session/)
  })

  it('revokes after confirmation', () => {
    vi.spyOn(window, 'confirm').mockReturnValue(true)
    render(<AgentsIndex agents={agents} new_token={null} />)

    fireEvent.click(screen.getByRole('button', { name: 'Revoke' }))

    expect(patch).toHaveBeenCalledWith('/agents/1/revoke')
  })
})
