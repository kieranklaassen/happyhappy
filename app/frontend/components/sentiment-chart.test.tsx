import { render, screen, within } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import SentimentChart, { type DayCounts } from './sentiment-chart'

function day(date: string, overrides: Partial<Omit<DayCounts, 'date'>> = {}): DayCounts {
  return {
    date,
    complaint: 0,
    praise: 0,
    question: 0,
    neutral: 0,
    relieved: 0,
    total: 0,
    ...overrides,
  }
}

describe('SentimentChart', () => {
  it('renders an empty list and legend without date labels when days is empty', () => {
    render(<SentimentChart days={[]} />)

    const figure = screen.getByRole('figure')
    const list = within(figure).getByRole('list', { name: 'Items per day by sentiment' })
    expect(within(list).queryAllByRole('listitem')).toHaveLength(0)

    for (const label of ['Complaint', 'Praise', 'Relieved', 'Question', 'Neutral', 'Unclassified']) {
      expect(within(figure).getByText(label)).toBeInTheDocument()
    }
    expect(figure.querySelector('div[aria-hidden="true"]')).toBeNull()
  })

  it('labels each day with pluralization, non-zero sentiments in order, and unclassified remainder', () => {
    render(
      <SentimentChart
        days={[
          day('2026-09-20', { total: 0 }),
          day('2026-09-21', { complaint: 1, total: 1 }),
          day('2026-09-22', { complaint: 2, praise: 1, relieved: 1, question: 1, neutral: 1, total: 6 }),
          day('2026-09-23', { complaint: 1, praise: 2, total: 5 }),
          day('2026-09-24', { total: 2 }),
        ]}
      />,
    )

    const bars = screen.getAllByRole('listitem')
    expect(bars).toHaveLength(5)

    const expectedLabels = [
      '2026-09-20: 0 items',
      '2026-09-21: 1 item (1 complaint)',
      '2026-09-22: 6 items (2 complaint, 1 praise, 1 relieved, 1 question, 1 neutral)',
      '2026-09-23: 5 items (1 complaint, 2 praise, 2 unclassified)',
      '2026-09-24: 2 items (2 unclassified)',
    ]

    bars.forEach((bar, index) => {
      expect(bar).toHaveAccessibleName(expectedLabels[index])
      expect(bar).toHaveAttribute('title', expectedLabels[index])
    })
  })

  it('scales bar heights against the busiest day and segment heights within each bar', () => {
    render(
      <SentimentChart
        days={[
          day('2026-09-21', { complaint: 1, praise: 1, total: 4 }),
          day('2026-09-22', { relieved: 2, total: 2 }),
          day('2026-09-23', { total: 0 }),
        ]}
      />,
    )

    const bars = screen.getAllByRole('listitem')

    const tallestBar = bars[0].firstElementChild as HTMLElement
    expect(tallestBar.style.height).toBe('100%')
    const tallestSegments = Array.from(tallestBar.children) as HTMLElement[]
    expect(tallestSegments).toHaveLength(2)
    expect(tallestSegments[0]).toHaveClass('bg-red-500')
    expect(tallestSegments[0].style.height).toBe('25%')
    expect(tallestSegments[1]).toHaveClass('bg-emerald-500')
    expect(tallestSegments[1].style.height).toBe('25%')

    const halfBar = bars[1].firstElementChild as HTMLElement
    expect(halfBar.style.height).toBe('50%')
    const halfSegments = Array.from(halfBar.children) as HTMLElement[]
    expect(halfSegments).toHaveLength(1)
    expect(halfSegments[0]).toHaveClass('bg-cyan-400')
    expect(halfSegments[0].style.height).toBe('100%')

    const zeroBar = bars[2].firstElementChild as HTMLElement
    expect(zeroBar.style.height).toBe('0%')
    expect(zeroBar.children).toHaveLength(0)
  })

  it('avoids division by zero when every day has zero items', () => {
    render(<SentimentChart days={[day('2026-09-20', { total: 0 }), day('2026-09-21', { total: 0 })]} />)

    for (const bar of screen.getAllByRole('listitem')) {
      const column = bar.firstElementChild as HTMLElement
      expect(column.style.height).toBe('0%')
      expect(column.children).toHaveLength(0)
    }
  })

  it('shows the first and last dates in an aria-hidden footer when days are present', () => {
    render(
      <SentimentChart
        days={[
          day('2026-09-01', { complaint: 1, total: 1 }),
          day('2026-09-15', { praise: 1, total: 1 }),
          day('2026-09-30', { neutral: 1, total: 1 }),
        ]}
      />,
    )

    const footer = screen.getByRole('figure').querySelector('div[aria-hidden="true"]')
    expect(footer).not.toBeNull()
    expect(within(footer as HTMLElement).getByText('2026-09-01')).toBeInTheDocument()
    expect(within(footer as HTMLElement).getByText('2026-09-30')).toBeInTheDocument()
    expect(within(footer as HTMLElement).queryByText('2026-09-15')).not.toBeInTheDocument()
  })

  it('does not report a negative unclassified count if sentiment counts exceed total', () => {
    render(<SentimentChart days={[day('2026-09-25', { complaint: 2, praise: 1, total: 2 })]} />)

    expect(screen.getByRole('listitem')).toHaveAccessibleName('2026-09-25: 2 items (2 complaint, 1 praise)')
  })
})
