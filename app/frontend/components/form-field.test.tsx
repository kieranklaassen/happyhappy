import { render, screen } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { FlashData } from '../types'
import { Field, FlashNotice } from './form-field'

let pageProps: { flash?: FlashData } = { flash: {} }

vi.mock('@inertiajs/react', () => ({
  usePage: () => ({ props: pageProps }),
}))

describe('Field', () => {
  it('associates the label with its child control and omits optional hint and alert', () => {
    render(
      <Field label="Product name" htmlFor="product_name">
        <input id="product_name" name="name" />
      </Field>,
    )

    expect(screen.getByLabelText('Product name')).toHaveAttribute('name', 'name')
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
  })

  it('renders hint content when provided', () => {
    render(
      <Field label="Slug" htmlFor="product_slug" hint={<span>Used in URLs</span>}>
        <input id="product_slug" />
      </Field>,
    )

    expect(screen.getByText('Used in URLs')).toBeInTheDocument()
  })

  it('renders a prefixed alert joining multiple errors and hides it when error is empty', () => {
    const { rerender } = render(
      <Field label="Email" htmlFor="user_email" error={[]}>
        <input id="user_email" />
      </Field>,
    )
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()

    rerender(
      <Field label="Email" htmlFor="user_email" error={["can't be blank"]}>
        <input id="user_email" />
      </Field>,
    )
    expect(screen.getByRole('alert')).toHaveTextContent("Email can't be blank")

    rerender(
      <Field label="Email" htmlFor="user_email" error={['is too short', 'is invalid']}>
        <input id="user_email" />
      </Field>,
    )
    expect(screen.getByRole('alert')).toHaveTextContent('Email is too short, is invalid')
  })
})

describe('FlashNotice', () => {
  beforeEach(() => {
    pageProps = { flash: {} }
  })

  it('renders nothing when flash is empty or missing', () => {
    const { container, rerender } = render(<FlashNotice />)
    expect(container).toBeEmptyDOMElement()

    pageProps = {}
    rerender(<FlashNotice />)
    expect(container).toBeEmptyDOMElement()
  })

  it('renders a status message for flash.notice', () => {
    pageProps = { flash: { notice: 'Saved changes.' } }
    render(<FlashNotice />)

    expect(screen.getByRole('status')).toHaveTextContent('Saved changes.')
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
  })

  it('renders an alert message for flash.alert', () => {
    pageProps = { flash: { alert: 'Could not save.' } }
    render(<FlashNotice />)

    expect(screen.getByRole('alert')).toHaveTextContent('Could not save.')
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
  })

  it('renders both notice and alert when both are present', () => {
    pageProps = { flash: { notice: 'Draft saved.', alert: 'Webhook delivery failed.' } }
    render(<FlashNotice />)

    expect(screen.getByRole('status')).toHaveTextContent('Draft saved.')
    expect(screen.getByRole('alert')).toHaveTextContent('Webhook delivery failed.')
  })
})
