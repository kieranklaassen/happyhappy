import { Head, router, useForm, usePage } from '@inertiajs/react'
import { type FormEvent, useState } from 'react'
import AppNav from '../../components/app-nav'
import type { FlashData } from '../../types'

export interface AgentRow {
  id: number
  name: string
  created_at: string
  last_used_at: string | null
  revoked_at: string | null
  claimed_count: number
}

export interface NewToken {
  agent_id: number
  name: string
  token: string
}

interface AgentsPageProps {
  agents: AgentRow[]
  new_token: NewToken | null
}

interface SharedPageProps {
  flash: FlashData
  [key: string]: unknown
}

function formatTime(iso: string | null): string {
  return iso ? new Date(iso).toLocaleString() : 'Never'
}

function TokenOnce({ newToken }: { newToken: NewToken }) {
  const [copied, setCopied] = useState(false)

  async function copy() {
    await navigator.clipboard.writeText(newToken.token)
    setCopied(true)
  }

  return (
    <section
      aria-labelledby="new-token-heading"
      className="flex flex-col gap-3 rounded border border-amber-300 bg-amber-50 p-4"
    >
      <h2 id="new-token-heading" className="font-semibold text-gray-900">
        Token for {newToken.name}
      </h2>
      <p className="text-sm text-gray-700">
        Copy this token now. It is shown only once and cannot be recovered; issue a new agent if it is lost.
      </p>
      <div className="flex items-center gap-2">
        <code data-testid="new-token" className="flex-1 break-all rounded bg-white px-3 py-2 font-mono text-sm">
          {newToken.token}
        </code>
        <button type="button" onClick={copy} className="rounded border border-gray-300 bg-white px-3 py-2 text-sm">
          {copied ? 'Copied' : 'Copy'}
        </button>
      </div>
      <p className="text-sm text-gray-700">
        Agents send it as <code className="font-mono">Authorization: Bearer &lt;token&gt;</code>.
      </p>
    </section>
  )
}

export default function AgentsIndex({ agents, new_token }: AgentsPageProps) {
  const { flash } = usePage<SharedPageProps>().props
  const form = useForm({ name: '' })

  function submit(event: FormEvent) {
    event.preventDefault()
    form.post('/agents', { onSuccess: () => form.reset() })
  }

  function revoke(agent: AgentRow) {
    if (window.confirm(`Revoke ${agent.name}? It will be cut off immediately.`)) {
      router.patch(`/agents/${agent.id}/revoke`)
    }
  }

  return (
    <>
      <Head title="Agents" />
      <AppNav />
      <main className="mx-auto flex max-w-4xl flex-col gap-6 px-6 py-8">
        <header className="flex flex-col gap-1">
          <h1 className="text-2xl font-bold tracking-tight text-gray-900">Agents</h1>
          <p className="text-sm text-gray-600">
            Each agent gets its own token to read, claim, and report on items over MCP.
          </p>
        </header>

        {flash.notice && (
          <p role="status" className="rounded bg-green-50 px-3 py-2 text-sm text-green-800">
            {flash.notice}
          </p>
        )}

        {new_token && <TokenOnce newToken={new_token} />}

        <form onSubmit={submit} className="flex items-end gap-3">
          <label className="flex flex-1 flex-col gap-1 text-sm">
            Agent name
            <input
              type="text"
              name="name"
              required
              value={form.data.name}
              onChange={(e) => form.setData('name', e.target.value)}
              placeholder="Cursor"
              className="rounded border border-gray-300 px-3 py-2"
            />
            {form.errors.name && (
              <span role="alert" className="text-red-700">
                {form.errors.name}
              </span>
            )}
          </label>
          <button
            type="submit"
            disabled={form.processing}
            className="rounded bg-gray-900 px-3 py-2 text-sm text-white disabled:opacity-50"
          >
            Issue token
          </button>
        </form>

        {agents.length === 0 ? (
          <p className="text-sm text-gray-600">No agents yet.</p>
        ) : (
          <table className="w-full text-left text-sm">
            <thead className="border-b border-gray-200 text-gray-500">
              <tr>
                <th className="py-2 font-medium">Name</th>
                <th className="py-2 font-medium">Last used</th>
                <th className="py-2 font-medium">Claimed items</th>
                <th className="py-2 font-medium">Status</th>
                <th className="py-2" />
              </tr>
            </thead>
            <tbody>
              {agents.map((agent) => (
                <tr key={agent.id} className="border-b border-gray-100">
                  <td className="py-2 font-medium text-gray-900">{agent.name}</td>
                  <td className="py-2 text-gray-600">{formatTime(agent.last_used_at)}</td>
                  <td className="py-2 text-gray-600">{agent.claimed_count}</td>
                  <td className="py-2">
                    {agent.revoked_at ? (
                      <span className="text-gray-500">Revoked {formatTime(agent.revoked_at)}</span>
                    ) : (
                      <span className="text-green-700">Active</span>
                    )}
                  </td>
                  <td className="py-2 text-right">
                    {!agent.revoked_at && (
                      <button
                        type="button"
                        onClick={() => revoke(agent)}
                        className="rounded border border-red-200 px-3 py-1 text-red-700 hover:bg-red-50"
                      >
                        Revoke
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </main>
    </>
  )
}
