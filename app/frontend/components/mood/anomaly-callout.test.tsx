import { render, screen } from '@testing-library/react'
import { type ReactNode } from 'react'
import { describe, expect, it, vi } from 'vitest'
import { anomaly } from '../../test/anomaly-fixture'
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

  it('is sunny for a surge of happy customers, including moods it does not know yet', () => {
    const { rerender } = render(<AnomalyCallout anomalies={[anomaly({ metric: 'mood_share', dimension: 'beaming', label: 'Beaming customers', share: true })]} />)
    expect(screen.getByRole('complementary', { name: 'Sunny spell for Cora' })).toBeInTheDocument()

    rerender(<AnomalyCallout anomalies={[anomaly({ metric: 'mood_share', dimension: 'relieved', label: 'Relieved customers', share: true, severity: 'low' })]} />)
    expect(screen.getByRole('complementary', { name: 'Sunny spell for Cora' })).toHaveTextContent('Relieved customers')
  })

  it('links to the rest of the product anomalies and renders nothing without any', () => {
    const { container, rerender } = render(<AnomalyCallout anomalies={[anomaly(), anomaly({ id: 13, severity: 'low' })]} />)
    expect(screen.getByRole('link', { name: '+1 more' })).toHaveAttribute('href', '/items?anomaly=active&product=cora')

    rerender(<AnomalyCallout anomalies={[]} />)
    expect(container).toBeEmptyDOMElement()
  })
})
