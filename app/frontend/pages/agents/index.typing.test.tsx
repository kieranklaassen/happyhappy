import { router } from '@inertiajs/react'
import { act, fireEvent, render, screen } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import AgentsIndex from './index'

// index.test.tsx mocks useForm. It stays real here, so the name field behaves as it does on the page that ships.
vi.mock('@inertiajs/react', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@inertiajs/react')>()),
  Head: () => null,
  usePage: () => ({ url: '/agents', props: { flash: {} } }),
}))

const post = vi.spyOn(router, 'post').mockImplementation(() => {})

beforeEach(() => {
  post.mockClear()
})

function nameField() {
  return screen.getByRole<HTMLInputElement>('textbox')
}

function type(name: string) {
  fireEvent.change(nameField(), { target: { value: name } })
}

// Adds an agent, with the request still open until the returned function says it succeeded.
function startAdd() {
  fireEvent.submit(nameField().form!)
  const options = post.mock.lastCall![2]!
  act(() => void options.onStart?.({} as never))
  return async () => {
    await act(async () => void (await options.onSuccess?.({} as never)))
    act(() => void options.onFinish?.({} as never))
  }
}

describe('The agent name field', () => {
  beforeEach(() => {
    render(<AgentsIndex agents={[]} new_token={null} />)
  })

  it('is blank again once the agent is added', async () => {
    type('Cursor')
    const succeed = startAdd()
    await succeed()

    expect(nameField()).toHaveValue('')
  })

  it('keeps a name typed while an agent is being added, ready for the next add', async () => {
    type('Cursor')
    const succeed = startAdd()
    type('Reviewer')
    await succeed()

    expect(nameField()).toHaveValue('Reviewer')
    startAdd()
    expect(post.mock.calls[1].slice(0, 2)).toEqual(['/agents', { name: 'Reviewer' }])
  })

  it('is blank again after a later add, too', async () => {
    type('Cursor')
    const first = startAdd()
    type('Reviewer')
    await first()
    const second = startAdd()
    await second()

    expect(nameField()).toHaveValue('')
  })

  it('keeps a rejected name', () => {
    type('Cursor')
    startAdd()
    const options = post.mock.calls[0][2]!
    act(() => void options.onError?.({ name: 'Name has already been taken' } as never))
    act(() => void options.onFinish?.({} as never))

    expect(nameField()).toHaveValue('Cursor')
    expect(screen.getByRole('alert')).toHaveTextContent('Name has already been taken')
  })
})
