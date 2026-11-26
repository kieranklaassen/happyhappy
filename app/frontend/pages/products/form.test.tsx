import { router } from '@inertiajs/react'
import { act, fireEvent, render, screen } from '@testing-library/react'
import { type ComponentProps, type ReactNode } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import ProductForm from './form'

// useForm stays real, so the transform, processing state and error handling are the ones the page ships with.
vi.mock('@inertiajs/react', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@inertiajs/react')>()),
  Head: ({ title }: { title: string }) => <title>{title}</title>,
  usePage: () => ({ url: '/products', props: { flash: {} } }),
  Link: ({ href, children }: { href: string; children: ReactNode }) => <a href={href}>{children}</a>,
}))

type Product = ComponentProps<typeof ProductForm>['product']

const newProduct: Product = {
  id: null,
  name: null,
  slug: null,
  description: null,
  hint_words: [],
  search_blurb: null,
  slack_channel_id: null,
  alert_channel_id: null,
  alert_mention_ids: [],
  escalation_threshold: null,
  digest_hour: 9,
}

const submittedNew = {
  name: '',
  slug: '',
  description: '',
  hint_words: '',
  search_blurb: '',
  slack_channel_id: '',
  alert_channel_id: '',
  alert_mention_ids: '',
  escalation_threshold: '',
  digest_hour: '9',
}

const storedProduct: Product = {
  id: 7,
  name: 'Cora',
  slug: 'cora',
  description: 'Email assistant.',
  hint_words: ['brief', 'inbox zero'],
  search_blurb: 'Cora assistant',
  slack_channel_id: 'C1',
  alert_channel_id: 'C2',
  alert_mention_ids: ['U1', 'S2'],
  escalation_threshold: 0.75,
  digest_hour: 17,
}

const submittedStored = {
  name: 'Cora',
  slug: 'cora',
  description: 'Email assistant.',
  hint_words: 'brief, inbox zero',
  search_blurb: 'Cora assistant',
  slack_channel_id: 'C1',
  alert_channel_id: 'C2',
  alert_mention_ids: 'U1, S2',
  escalation_threshold: '0.75',
  digest_hour: '17',
}

// Every field in the order it appears. `attributes` are all the control's own attributes besides id, class and value.
const FIELDS = [
  { name: 'name', label: 'Name', hint: null, tag: 'INPUT', attributes: { required: '' }, edited: 'Spiral' },
  {
    name: 'slug',
    label: 'Slug',
    hint: 'Leave blank to derive it from the name.',
    tag: 'INPUT',
    attributes: {},
    edited: 'spiral',
  },
  {
    name: 'description',
    label: 'Description',
    hint: 'One or two sentences. The classifier reads this to decide whether a message is about the product.',
    tag: 'TEXTAREA',
    attributes: { rows: '3' },
    edited: 'Writes\ndrafts.',
  },
  {
    name: 'hint_words',
    label: 'Hint words',
    hint: 'Aliases and feature names, separated by commas or new lines.',
    tag: 'TEXTAREA',
    attributes: { rows: '2' },
    edited: 'draft\nvoice',
  },
  {
    name: 'search_blurb',
    label: 'Search words',
    hint: 'What people call it, 40 characters at most, for example Cora assistant. Feed search reads these words as naming the product. Leave out words people search for, such as email or inbox. Blank uses the name.',
    tag: 'INPUT',
    attributes: { maxlength: '40' },
    edited: 'Spiral writer',
  },
  {
    name: 'slack_channel_id',
    label: 'Slack support channel id',
    hint: 'Escalations and the daily digest post here, for example C0123456789.',
    tag: 'INPUT',
    attributes: {},
    edited: 'C8',
  },
  {
    name: 'alert_channel_id',
    label: 'Incident alert channel id',
    hint: 'Bad-news spikes open an incident and ping this channel once, for example C0AGCDCD6KG. Leave empty for no incident pings.',
    tag: 'INPUT',
    attributes: {},
    edited: 'C9',
  },
  {
    name: 'alert_mention_ids',
    label: 'On-call Slack IDs',
    hint: 'Mentioned in each incident ping. User IDs start with U (Copy member ID in Slack), user group IDs with S. Separate with commas.',
    tag: 'INPUT',
    attributes: {},
    edited: 'U8, S9',
  },
  {
    name: 'escalation_threshold',
    label: 'Escalation threshold',
    hint: 'Anger probability from 0 to 1. Blank uses the default, 0.8.',
    tag: 'INPUT',
    attributes: { type: 'number', min: '0', max: '1', step: '0.01' },
    edited: '0.5',
  },
  {
    name: 'digest_hour',
    label: 'Digest time',
    hint: 'Daily, in the app time zone.',
    tag: 'SELECT',
    attributes: {},
    edited: '22',
  },
] as const

const MODES = [
  {
    mode: 'new',
    product: newProduct,
    submitted: submittedNew,
    title: 'Add product',
    button: 'Create product',
    method: 'post',
    url: '/products',
  },
  {
    mode: 'edit',
    product: storedProduct,
    submitted: submittedStored,
    title: 'Edit Cora',
    button: 'Save product',
    method: 'patch',
    url: '/products/7',
  },
] as const

type Control = HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement

describe.each(MODES)('Product form ($mode)', ({ product, submitted, title, button, method, url }) => {
  const visits = {
    post: vi.spyOn(router, 'post').mockImplementation(() => {}),
    patch: vi.spyOn(router, 'patch').mockImplementation(() => {}),
  }

  beforeEach(() => {
    visits.post.mockClear()
    visits.patch.mockClear()
  })

  function renderPage() {
    return render(<ProductForm product={product} default_escalation_threshold={0.8} />)
  }

  function control(label: string) {
    return screen.getByLabelText<Control>(label, { exact: true })
  }

  function submitButton() {
    return screen.getByRole('button', { name: button })
  }

  function submit() {
    fireEvent.submit(submitButton().closest('form')!)
    return visits[method].mock.calls[0][2]!
  }

  it('titles the page and links back to the products', () => {
    renderPage()

    expect(document.title).toBe(title)
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(title)
    expect(screen.getByRole('link', { name: 'Cancel' })).toHaveAttribute('href', '/products')
  })

  it('renders every field in order', () => {
    const { container } = renderPage()

    const controls = Array.from(container.querySelectorAll('form :is(input, textarea, select)'))
    expect(controls.map((element) => element.id)).toEqual(FIELDS.map(({ name }) => `product_${name}`))
  })

  it.each(FIELDS)('labels, hints and limits $name', ({ name, label, hint, tag, attributes }) => {
    renderPage()

    const element = control(label)
    expect(element.id).toBe(`product_${name}`)
    expect(element.tagName).toBe(tag)
    const own = Array.from(element.attributes, (attribute) => [attribute.name, attribute.value] as const)
    expect(Object.fromEntries(own.filter(([key]) => !['id', 'class', 'value'].includes(key)))).toEqual(attributes)
    const paragraphs = Array.from(element.parentElement!.querySelectorAll('p'), (p) => p.textContent)
    expect(paragraphs).toEqual(hint === null ? [] : [hint])
  })

  it('offers every hour of the day', () => {
    renderPage()

    const options = Array.from(control('Digest time').querySelectorAll('option'), ({ value, text }) => [value, text])
    expect(options).toEqual(
      Array.from({ length: 24 }, (_, hour) => [`${hour}`, hour < 10 ? `0${hour}:00` : `${hour}:00`]),
    )
  })

  it('submits the values it shows, under product', () => {
    renderPage()

    expect(Object.fromEntries(FIELDS.map(({ name, label }) => [name, control(label).value]))).toEqual(submitted)
    submit()

    expect(visits[method]).toHaveBeenCalledExactlyOnceWith(url, { product: submitted }, expect.any(Object))
    expect(visits[method === 'post' ? 'patch' : 'post']).not.toHaveBeenCalled()
  })

  it.each(FIELDS)('submits an edited $name and leaves the rest alone', ({ name, label, edited }) => {
    renderPage()

    fireEvent.change(control(label), { target: { value: edited } })
    submit()

    expect(control(label).value).toBe(edited)
    expect(visits[method]).toHaveBeenCalledExactlyOnceWith(
      url,
      { product: { ...submitted, [name]: edited } },
      expect.any(Object),
    )
  })

  it('shows each field its own validation errors', () => {
    renderPage()
    const options = submit()
    expect(screen.queryAllByRole('alert')).toEqual([])

    const errors = Object.fromEntries(FIELDS.map(({ name }) => [name, [`rejects ${name}`, 'is wrong']]))
    act(() => {
      // Rails sends a list of messages per field.
      void options.onError?.(errors as never)
    })

    FIELDS.forEach(({ name, label }) => {
      expect(control(label).parentElement!.querySelector('[role="alert"]')).toHaveTextContent(
        `${label} rejects ${name}, is wrong`,
      )
    })
    expect(screen.getAllByRole('alert')).toHaveLength(FIELDS.length)
  })

  it('cannot be submitted again while it is being saved', () => {
    renderPage()
    expect(submitButton()).toBeEnabled()
    const options = submit()

    act(() => {
      void options.onStart?.({} as never)
    })

    expect(submitButton()).toBeDisabled()
  })
})
