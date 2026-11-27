import { describe, expect, it } from 'vitest'
import { deliveryBadge, eventLabel } from './webhooks'

describe('deliveryBadge', () => {
  it('calls a pending delivery queued until its first attempt, then retrying', () => {
    expect(deliveryBadge({ status: 'pending', attempts: 0 }).label).toBe('Queued')
    expect(deliveryBadge({ status: 'pending', attempts: 1 }).label).toBe('Retrying')
  })

  it('reports the outcome however many attempts it took', () => {
    expect(deliveryBadge({ status: 'succeeded', attempts: 1 }).label).toBe('Delivered')
    expect(deliveryBadge({ status: 'succeeded', attempts: 5 }).label).toBe('Delivered')
    expect(deliveryBadge({ status: 'failed', attempts: 0 }).label).toBe('Failed')
  })
})

describe('eventLabel', () => {
  it.each([
    ['item.arrived', 'Item arrived'],
    ['item.status_changed', 'Status changed'],
    ['anomaly.detected', 'Anomaly detected'],
    ['incident.resolved', 'Incident resolved'],
  ] as const)('names %s as "%s"', (event, label) => {
    expect(eventLabel(event)).toBe(label)
  })
})
