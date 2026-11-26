import { router } from '@inertiajs/react'
import { act, fireEvent, render, screen, within } from '@testing-library/react'
import { type ComponentProps } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import CategoriesIndex from './index'

const page = vi.hoisted(() => ({ flash: {} as { notice?: string; alert?: string } }))

// useForm stays real, so the transform, dirty and processing state, and error handling are the ones the page ships with.
vi.mock('@inertiajs/react', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@inertiajs/react')>()),
  Head: ({ title }: { title: string }) => <title>{title}</title>,
  usePage: () => ({ url: '/categories', props: { flash: page.flash } }),
}))

type Props = ComponentProps<typeof CategoriesIndex>
type Category = Props['categories'][number]

const bug: Category = {
  id: 3,
  name: 'bug',
  description: 'Something is broken.',
  search_blurb: 'bug, broken',
  position: 1,
  retired_at: null,
  item_count: 12,
}

const praise: Category = {
  id: 8,
  name: 'praise',
  description: null,
  search_blurb: null,
  position: 5,
  retired_at: null,
  item_count: 0,
}

const pricing: Category = {
  id: 21,
  name: 'pricing',
  description: 'Old label.',
  search_blurb: null,
  position: 9,
  retired_at: '2026-09-01T12:00:00Z',
  item_count: 4,
}

const legal: Category = { ...pricing, id: 22, name: 'legal', item_count: 0 }

const SEARCH_HINT = 'Words that name it in feed search, 40 characters at most. Blank uses the name.'

const EDIT_FIELDS = [
  { name: 'position', label: 'Order', hint: null, attributes: { type: 'number', step: '1' }, edited: '-2' },
  { name: 'name', label: 'Name', hint: '12 items', attributes: { required: '' }, edited: 'defect' },
  { name: 'description', label: 'Description', hint: null, attributes: {}, edited: 'It fails.' },
  { name: 'search_blurb', label: 'Search words', hint: SEARCH_HINT, attributes: { maxlength: '40' }, edited: 'defect' },
] as const

const NEW_FIELDS = [
  { name: 'name', label: 'Name', hint: null, attributes: { required: '' }, edited: 'security' },
  { name: 'description', label: 'Description', hint: null, attributes: {}, edited: 'Account safety.' },
  { name: 'search_blurb', label: 'Search words', hint: SEARCH_HINT, attributes: { maxlength: '40' }, edited: 'hacked' },
] as const

const storedBug = { name: 'bug', description: 'Something is broken.', search_blurb: 'bug, broken', position: '1' }
const blank = { name: '', description: '', search_blurb: '' }

const visits = {
  post: vi.spyOn(router, 'post').mockImplementation(() => {}),
  patch: vi.spyOn(router, 'patch').mockImplementation(() => {}),
}
const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false)

beforeEach(() => {
  vi.clearAllMocks()
  page.flash = {}
})

function renderPage(props: Partial<Props> = {}) {
  return render(<CategoriesIndex categories={[bug, praise]} retired_categories={[pricing, legal]} {...props} />)
}

function formNamed(name: string) {
  return screen.getByRole<HTMLFormElement>('form', { name })
}

function control(form: HTMLElement, label: string) {
  return within(form).getByLabelText<HTMLInputElement>(label, { exact: true })
}

function button(container: HTMLElement, name: string) {
  return within(container).getByRole('button', { name })
}

function change(form: HTMLElement, label: string, value: string) {
  fireEvent.change(control(form, label), { target: { value } })
}

function values(form: HTMLElement, fields: readonly { name: string; label: string }[]) {
  return Object.fromEntries(fields.map(({ name, label }) => [name, control(form, label).value]))
}

function ownAttributes(element: Element) {
  const own = Array.from(element.attributes, ({ name, value }) => [name, value] as const)
  return Object.fromEntries(own.filter(([name]) => !['id', 'class', 'value'].includes(name)))
}

function hints(element: Element) {
  return Array.from(element.parentElement!.querySelectorAll('p'), (p) => p.textContent)
}

// Rails sends a list of messages per field.
function rejection(fields: readonly { name: string }[]) {
  return Object.fromEntries(fields.map(({ name }) => [name, [`rejects ${name}`, 'is wrong']])) as never
}

function alerts(form: HTMLElement) {
  return within(form)
    .queryAllByRole('alert')
    .map((alert) => alert.textContent)
}

describe('Categories index', () => {
  it('titles and explains the page', () => {
    renderPage()

    expect(document.title).toBe('Categories')
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Categories')
    expect(
      screen.getByText('One list for every product. The classifier picks from the active categories.'),
    ).toBeInTheDocument()
    expect(screen.getByRole('link', { current: 'page' })).toHaveAttribute('href', '/categories')
    expect(within(screen.getByRole('main')).queryAllByRole('link')).toEqual([])
  })

  it('shows what the last change did', () => {
    page.flash = { notice: 'Saved bug.', alert: 'Not allowed.' }
    renderPage()

    expect(screen.getByRole('status')).toHaveTextContent('Saved bug.')
    expect(screen.getByRole('alert')).toHaveTextContent('Not allowed.')
  })

  it('lists active categories in the order given, then the form to add one', () => {
    renderPage({ categories: [praise, bug] })

    const names = screen.getAllByRole('form').map((form) => form.getAttribute('aria-label'))
    expect(names).toEqual(['Edit praise', 'Edit bug', 'Add category'])
  })

  it('still offers to add a category when there are none', () => {
    renderPage({ categories: [], retired_categories: [] })

    expect(screen.getAllByRole('form')).toEqual([formNamed('Add category')])
    expect(screen.queryByRole('heading', { name: 'Retired' })).not.toBeInTheDocument()
    expect(screen.getAllByRole('button')).toEqual([screen.getByRole('button', { name: 'Add category' })])
  })
})

describe('editing a category', () => {
  function save() {
    fireEvent.submit(formNamed('Edit bug'))
    return visits.patch.mock.calls[0][2]!
  }

  it('shows the stored values, with blanks for what is missing', () => {
    renderPage()

    expect(values(formNamed('Edit bug'), EDIT_FIELDS)).toEqual(storedBug)
    expect(values(formNamed('Edit praise'), EDIT_FIELDS)).toEqual({ ...blank, name: 'praise', position: '5' })
    expect(hints(control(formNamed('Edit praise'), 'Name'))).toEqual(['0 items'])
  })

  it('counts one item in the singular', () => {
    renderPage({ categories: [{ ...bug, item_count: 1 }] })

    expect(hints(control(formNamed('Edit bug'), 'Name'))).toEqual(['1 item'])
  })

  it('renders its fields in order', () => {
    renderPage()

    const ids = Array.from(formNamed('Edit bug').querySelectorAll('input'), ({ id }) => id)
    expect(ids).toEqual(EDIT_FIELDS.map(({ name }) => `category_3_${name}`))
  })

  it.each(EDIT_FIELDS)('labels, hints and limits $name', ({ label, hint, attributes }) => {
    renderPage()

    const element = control(formNamed('Edit bug'), label)
    expect(ownAttributes(element)).toEqual(attributes)
    expect(hints(element)).toEqual(hint === null ? [] : [hint])
  })

  it.each(EDIT_FIELDS)('saves an edited $name with the rest unchanged', ({ name, label, edited }) => {
    renderPage()
    const form = formNamed('Edit bug')

    change(form, label, edited)
    expect(control(form, label).value).toBe(edited)
    save()

    expect(visits.patch).toHaveBeenCalledExactlyOnceWith(
      '/categories/3',
      { category: { ...storedBug, [name]: edited } },
      expect.objectContaining({ preserveScroll: true, errorBag: 'category_3' }),
    )
    expect(visits.post).not.toHaveBeenCalled()
    expect(values(formNamed('Edit praise'), EDIT_FIELDS)).toEqual({ ...blank, name: 'praise', position: '5' })
  })

  it('is sent by its Save button', () => {
    renderPage()
    const form = formNamed('Edit bug')

    change(form, 'Name', 'defect')
    fireEvent.click(button(form, 'Save'))

    expect(visits.patch).toHaveBeenCalledOnce()
  })

  it('can be saved only while something differs from what is stored', () => {
    renderPage()
    const form = formNamed('Edit bug')
    expect(button(form, 'Save')).toBeDisabled()

    change(form, 'Description', 'It fails.')
    expect(button(form, 'Save')).toBeEnabled()
    expect(button(formNamed('Edit praise'), 'Save')).toBeDisabled()

    change(form, 'Description', bug.description!)
    expect(button(form, 'Save')).toBeDisabled()
  })

  it('cannot be saved again while it is being saved', () => {
    renderPage()
    const form = formNamed('Edit bug')
    change(form, 'Name', 'defect')
    const options = save()

    act(() => void options.onStart?.({} as never))
    expect(button(form, 'Save')).toBeDisabled()

    act(() => void options.onFinish?.({} as never))
    expect(button(form, 'Save')).toBeEnabled()
  })

  it('counts the saved values as stored from then on', async () => {
    renderPage()
    const form = formNamed('Edit bug')
    change(form, 'Name', 'defect')
    const options = save()

    await act(async () => void (await options.onSuccess?.({} as never)))

    expect(control(form, 'Name').value).toBe('defect')
    expect(button(form, 'Save')).toBeDisabled()
    change(form, 'Name', 'bug')
    expect(button(form, 'Save')).toBeEnabled()
  })

  // A reload, or the page a visit came back with: the same page with the rows the server has now.
  function reload(view: ReturnType<typeof renderPage>, changes: Partial<Category>) {
    view.rerender(<CategoriesIndex categories={[{ ...bug, ...changes }, praise]} retired_categories={[]} />)
  }

  it('keeps text typed while it is being saved, ready for the next save', async () => {
    const view = renderPage()
    const form = formNamed('Edit bug')
    change(form, 'Name', 'defect')
    const options = save()
    act(() => void options.onStart?.({} as never))

    change(form, 'Description', 'It fails.')
    reload(view, { name: 'defect' })
    await act(async () => void (await options.onSuccess?.({} as never)))
    act(() => void options.onFinish?.({} as never))

    expect(values(form, EDIT_FIELDS)).toEqual({ ...storedBug, name: 'defect', description: 'It fails.' })
    expect(button(form, 'Save')).toBeEnabled()
    fireEvent.submit(form)
    expect(visits.patch.mock.calls[1][1]).toEqual({
      category: { ...storedBug, name: 'defect', description: 'It fails.' },
    })
  })

  it('keeps a field typed back to its old value while it is being saved', async () => {
    const view = renderPage()
    const form = formNamed('Edit bug')
    change(form, 'Name', 'defect')
    const options = save()
    act(() => void options.onStart?.({} as never))

    change(form, 'Name', 'bug')
    reload(view, { name: 'defect' })
    await act(async () => void (await options.onSuccess?.({} as never)))
    act(() => void options.onFinish?.({} as never))

    expect(control(form, 'Name').value).toBe('bug')
    expect(button(form, 'Save')).toBeEnabled()
  })

  it.each([
    { typed: ' defect ', stored: 'defect' },
    { typed: ' bug ', stored: 'bug' },
  ])('shows "$stored" when the server stores "$typed" as that', async ({ typed, stored }) => {
    const view = renderPage()
    const form = formNamed('Edit bug')
    change(form, 'Name', typed)
    const options = save()
    act(() => void options.onStart?.({} as never))
    reload(view, { name: stored })
    await act(async () => void (await options.onSuccess?.({} as never)))
    act(() => void options.onFinish?.({} as never))

    expect(control(form, 'Name').value).toBe(stored)
    expect(button(form, 'Save')).toBeDisabled()
  })

  it('shows values the server changed', () => {
    const view = renderPage()
    const changed = { name: 'defect', description: null, search_blurb: 'defect', position: 4 }

    reload(view, changed)

    const form = formNamed('Edit defect')
    expect(values(form, EDIT_FIELDS)).toEqual({ ...changed, description: '', position: '4' })
    expect(button(form, 'Save')).toBeDisabled()
  })

  it('keeps what is being typed when the server changes the row', () => {
    const view = renderPage()
    const form = formNamed('Edit bug')
    change(form, 'Name', 'defect')

    reload(view, { name: 'fault', description: 'It fails.' })

    expect(values(form, EDIT_FIELDS)).toEqual({ ...storedBug, name: 'defect', description: 'It fails.' })
    expect(button(form, 'Save')).toBeEnabled()
    change(form, 'Name', 'fault')
    expect(button(form, 'Save')).toBeDisabled()
  })

  it('keeps a rejected edit when the server changed the row meanwhile', () => {
    const view = renderPage()
    const form = formNamed('Edit bug')
    change(form, 'Name', 'praise')
    const options = save()
    act(() => void options.onStart?.({} as never))
    reload(view, { name: 'fault', description: 'It fails.' })
    act(() => void options.onError?.(rejection(EDIT_FIELDS.slice(1, 2))))
    act(() => void options.onFinish?.({} as never))

    expect(values(form, EDIT_FIELDS)).toEqual({ ...storedBug, name: 'praise', description: 'It fails.' })
    expect(alerts(form)).toEqual(['Name rejects name, is wrong'])
    expect(button(form, 'Save')).toBeEnabled()
  })

  it('shows its own validation errors and keeps the edit', () => {
    renderPage()
    const form = formNamed('Edit bug')
    change(form, 'Name', 'praise')
    const options = save()

    act(() => void options.onError?.(rejection(EDIT_FIELDS)))

    EDIT_FIELDS.forEach(({ name, label }) => {
      expect(control(form, label).parentElement!.querySelector('[role="alert"]')).toHaveTextContent(
        `${label} rejects ${name}, is wrong`,
      )
    })
    expect(screen.getAllByRole('alert')).toHaveLength(EDIT_FIELDS.length)
    expect(control(form, 'Name').value).toBe('praise')
    expect(button(form, 'Save')).toBeEnabled()
  })
})

describe('adding a category', () => {
  // Clicking, unlike submitting the form directly, is stopped by a blank required name as it is in a browser.
  function add() {
    fireEvent.click(button(formNamed('Add category'), 'Add category'))
    return visits.post.mock.calls[0][2]!
  }

  it('starts blank, with its fields in order', () => {
    renderPage()
    const form = formNamed('Add category')

    expect(values(form, NEW_FIELDS)).toEqual(blank)
    const ids = Array.from(form.querySelectorAll('input'), ({ id }) => id)
    expect(ids).toEqual(NEW_FIELDS.map(({ name }) => `new_category_${name}`))
  })

  it.each(NEW_FIELDS)('labels, hints and limits $name', ({ label, hint, attributes }) => {
    renderPage()

    const element = control(formNamed('Add category'), label)
    expect(ownAttributes(element)).toEqual(attributes)
    expect(hints(element)).toEqual(hint === null ? [] : [hint])
  })

  it.each(NEW_FIELDS)('sends $name', ({ name, label, edited }) => {
    renderPage()
    const form = formNamed('Add category')

    change(form, 'Name', 'legal')
    change(form, label, edited)
    expect(control(form, label).value).toBe(edited)
    add()

    expect(visits.post).toHaveBeenCalledExactlyOnceWith(
      '/categories',
      { category: { ...blank, name: 'legal', [name]: edited } },
      expect.objectContaining({ preserveScroll: true, errorBag: 'new_category' }),
    )
    expect(visits.patch).not.toHaveBeenCalled()
  })

  it('sends everything typed into it', () => {
    renderPage()
    NEW_FIELDS.forEach(({ label, edited }) => change(formNamed('Add category'), label, edited))
    add()

    expect(visits.post).toHaveBeenCalledExactlyOnceWith(
      '/categories',
      { category: { name: 'security', description: 'Account safety.', search_blurb: 'hacked' } },
      expect.any(Object),
    )
  })

  it('is not sent without a name', () => {
    renderPage()
    const form = formNamed('Add category')

    fireEvent.click(button(form, 'Add category'))
    change(form, 'Description', 'Account safety.')
    fireEvent.click(button(form, 'Add category'))

    expect(visits.post).not.toHaveBeenCalled()
  })

  it('cannot be sent again while it is being added', () => {
    renderPage()
    const form = formNamed('Add category')
    expect(button(form, 'Add category')).toBeEnabled()
    change(form, 'Name', 'security')
    const options = add()

    act(() => void options.onStart?.({} as never))
    expect(button(form, 'Add category')).toBeDisabled()

    act(() => void options.onFinish?.({} as never))
    expect(button(form, 'Add category')).toBeEnabled()
  })

  it('is blank again once the category is added', async () => {
    renderPage()
    const form = formNamed('Add category')
    NEW_FIELDS.forEach(({ label, edited }) => change(form, label, edited))
    const options = add()

    await act(async () => void (await options.onSuccess?.({} as never)))

    expect(values(form, NEW_FIELDS)).toEqual(blank)
  })

  it('keeps text typed while a category is being added', async () => {
    renderPage()
    const form = formNamed('Add category')
    NEW_FIELDS.forEach(({ label, edited }) => change(form, label, edited))
    const options = add()
    act(() => void options.onStart?.({} as never))

    change(form, 'Name', 'privacy')
    await act(async () => void (await options.onSuccess?.({} as never)))
    act(() => void options.onFinish?.({} as never))

    expect(values(form, NEW_FIELDS)).toEqual({ ...blank, name: 'privacy' })
    fireEvent.click(button(form, 'Add category'))
    expect(visits.post.mock.calls[1][1]).toEqual({ category: { ...blank, name: 'privacy' } })
  })

  it('is blank again after a later add, too', async () => {
    renderPage()
    const form = formNamed('Add category')
    change(form, 'Name', 'security')
    const first = add()
    change(form, 'Name', 'privacy')
    await act(async () => void (await first.onSuccess?.({} as never)))

    add()
    await act(async () => void (await visits.post.mock.calls[1][2]!.onSuccess?.({} as never)))

    expect(values(form, NEW_FIELDS)).toEqual(blank)
  })

  it('shows its own validation errors and keeps what was typed', () => {
    renderPage()
    const form = formNamed('Add category')
    change(form, 'Name', 'bug')
    const options = add()

    act(() => void options.onError?.(rejection(NEW_FIELDS)))

    expect(alerts(form)).toEqual(NEW_FIELDS.map(({ name, label }) => `${label} rejects ${name}, is wrong`))
    NEW_FIELDS.forEach(({ name, label }) => {
      expect(control(form, label).parentElement).toHaveTextContent(`rejects ${name}`)
    })
    expect(screen.getAllByRole('alert')).toHaveLength(NEW_FIELDS.length)
    expect(control(form, 'Name').value).toBe('bug')
  })
})

describe('retiring and restoring a category', () => {
  it('retires the chosen category at once, without sending its edits', () => {
    renderPage()
    const form = formNamed('Edit praise')

    change(form, 'Name', 'thanks')
    fireEvent.click(button(form, 'Retire'))

    expect(visits.patch).toHaveBeenCalledExactlyOnceWith('/categories/8/retire', {}, { preserveScroll: true })
    expect(confirm).not.toHaveBeenCalled()
  })

  it('lists retired categories in the order given, apart from the active ones', () => {
    renderPage()
    const section = screen.getByRole('heading', { level: 2, name: 'Retired' }).parentElement!

    expect(
      within(section).getByText('Retired categories stay on past items but are left out of new classification.'),
    ).toBeInTheDocument()
    expect(
      within(section)
        .getAllByRole('listitem')
        .map((item) => item.querySelector('span')!.textContent),
    ).toEqual(['pricing (4 items)', 'legal (0 items)'])
    expect(screen.queryByRole('form', { name: 'Edit pricing' })).not.toBeInTheDocument()
  })

  it('counts one retired item in the singular', () => {
    renderPage({ retired_categories: [{ ...pricing, item_count: 1 }] })

    expect(screen.getByText('(1 item)')).toBeInTheDocument()
  })

  it('lists retired categories when no active ones are left', () => {
    renderPage({ categories: [] })

    expect(screen.getByRole('heading', { name: 'Retired' })).toBeInTheDocument()
  })

  it('leaves the retired list out when nothing is retired', () => {
    renderPage({ retired_categories: [] })

    expect(screen.queryByRole('heading', { name: 'Retired' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Restore' })).not.toBeInTheDocument()
  })

  it('restores the chosen category at once', () => {
    renderPage()
    const items = screen.getByRole('heading', { name: 'Retired' }).parentElement!.querySelectorAll('li')

    fireEvent.click(button(items[1], 'Restore'))

    expect(visits.patch).toHaveBeenCalledExactlyOnceWith('/categories/22/restore', {}, { preserveScroll: true })
    expect(confirm).not.toHaveBeenCalled()
  })
})
