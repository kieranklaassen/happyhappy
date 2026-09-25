import { render, screen } from '@testing-library/react'
import { type ReactNode } from 'react'
import { describe, expect, it, vi } from 'vitest'
import { anomaly, goodNews } from '../../test/anomaly-fixture'
import type { AnomalyHighlight } from '../../types/anomalies'
import AnomalyCallout from './anomaly-callout'

vi.mock('@inertiajs/react', () => ({
  Link: ({ href, children, ...rest }: { href: string; children: ReactNode }) => (
    <a href={href} {...rest}>
      {children}
    </a>
  ),
}))

describe('AnomalyCallout', () => {
  it('shows the weather, the metric, expected against actual, and a link to the items', () => {
    render(<AnomalyCallout anomalies={[anomaly()]} />)

    const callout = screen.getByRole('complementary', { name: 'Storm warning for Cora' })
    expect(callout).toHaveTextContent('Bug messages: 9 in the last hour, usually 0.4.')
    expect(callout).toHaveTextContent('High severity')
    expect(screen.getByRole('link', { name: 'See what happened' })).toHaveAttribute('href', '/items?anomaly=12')
    expect(screen.queryByRole('link', { name: /more/ })).not.toBeInTheDocument()
  })

  it('formats shares as percentages and names the source', () => {
    render(
      <AnomalyCallout
        anomalies={[
          anomaly({ metric: 'complaint_share', label: 'Complaint share', share: true, expected: 0.18, actual: 0.62, severity: 'medium', source: { id: 1, kind: 'slack', name: 'Community Slack' } }),
        ]}
      />,
    )

    expect(screen.getByRole('complementary', { name: 'Showers ahead for Cora' })).toHaveTextContent(
      'Complaint share on Community Slack: 62% in the last hour, usually 18%.',
    )
  })

  it('celebrates good news with sunshine and names the product', () => {
    render(<AnomalyCallout anomalies={[goodNews()]} />)

    const callout = screen.getByRole('complementary', { name: 'Good news for Thesis' })
    expect(callout).toHaveTextContent('Way more praise messages for Thesis: 12 in a day, usually 2.')
    expect(screen.getByRole('link', { name: 'See the love' })).toHaveAttribute('href', '/items?anomaly=21')
    expect(callout.querySelector('[data-weather]')).toHaveAttribute('data-weather', 'sunny')
  })

  it('brings out a rainbow for huge good news, including happy moods', () => {
    render(<AnomalyCallout anomalies={[goodNews({ metric: 'mood_share', dimension: 'beaming', label: 'Beaming customers', share: true, expected: 0.2, actual: 0.7, highlight: 'huge' })]} />)

    const callout = screen.getByRole('complementary', { name: 'Great news for Thesis' })
    expect(callout).toHaveTextContent('So much more beaming customers for Thesis: 70% in a day, usually 20%.')
    expect(callout.querySelector('[data-weather]')).toHaveAttribute('data-weather', 'rainbow')
  })

  it('never shows storm, rain, or warning wording for good news', () => {
    const highlights: AnomalyHighlight[] = ['notable', 'big', 'huge']
    for (const highlight of highlights) {
      const { container, unmount } = render(<AnomalyCallout anomalies={[goodNews({ highlight })]} />)
      expect(container).not.toHaveTextContent(/storm|warning|severity|showers|clouds|alert/i)
      expect(screen.getByRole('complementary').getAttribute('aria-label')).not.toMatch(/storm|warning|showers|clouds/i)
      expect(container.querySelector('.hh-rain')).toBeNull()
      expect(['sunny', 'rainbow']).toContain(container.querySelector('[data-weather]')?.getAttribute('data-weather'))
      unmount()
    }
  })

  it('is breezy and busier than usual for neutral spikes', () => {
    render(<AnomalyCallout anomalies={[anomaly({ metric: 'volume', dimension: null, label: 'Message volume', polarity: 'neutral', severity: null, expected: 5, actual: 14 })]} />)

    const callout = screen.getByRole('complementary', { name: 'Busier than usual for Cora' })
    expect(callout).toHaveTextContent('Message volume: 14 in the last hour, usually 5.')
    expect(callout).not.toHaveTextContent(/severity/)
    expect(callout.querySelector('[data-weather]')).toHaveAttribute('data-weather', 'breezy')
  })

  it('gathers clouds for low severity bad news', () => {
    render(<AnomalyCallout anomalies={[anomaly({ severity: 'low' })]} />)
    expect(screen.getByRole('complementary', { name: 'Clouds gathering for Cora' })).toHaveTextContent('Low severity')
  })

  it('links to the rest of the product anomalies and renders nothing without any', () => {
    const { container, rerender } = render(<AnomalyCallout anomalies={[anomaly(), anomaly({ id: 13, severity: 'low' })]} />)
    expect(screen.getByRole('link', { name: '+1 more' })).toHaveAttribute('href', '/items?anomaly=active&product=cora')

    rerender(<AnomalyCallout anomalies={[]} />)
    expect(container).toBeEmptyDOMElement()
  })
})
