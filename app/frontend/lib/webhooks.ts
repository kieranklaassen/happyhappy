export type WebhookEvent = 'item.arrived' | 'item.classified' | 'item.status_changed' | 'item.escalated' | 'agent.reported'
export type DeliveryEvent = WebhookEvent | 'webhook.test'
export type DeliveryStatus = 'pending' | 'succeeded' | 'failed'

export interface DeliveryRow {
  id: number
  event: DeliveryEvent
  status: DeliveryStatus
  attempts: number
  response_code: number | null
  last_error: string | null
  test: boolean
  item_event_id: number | null
  item_id: number | null
  created_at: string
  last_attempted_at: string | null
}

export interface EndpointRow {
  id: number
  name: string
  url: string
  active: boolean
  events: WebhookEvent[]
  product_ids: number[]
  category_ids: number[]
  sentiments: string[]
  last_delivery: DeliveryRow | null
}

export function eventLabel(event: DeliveryEvent): string {
  switch (event) {
    case 'item.arrived':
      return 'Item arrived'
    case 'item.classified':
      return 'Item classified'
    case 'item.status_changed':
      return 'Status changed'
    case 'item.escalated':
      return 'Escalated'
    case 'agent.reported':
      return 'Agent reported'
    case 'webhook.test':
      return 'Test send'
    default: {
      const unhandled: never = event
      throw new Error(`Unknown webhook event: ${String(unhandled)}`)
    }
  }
}

export function deliveryBadge({ status, attempts }: Pick<DeliveryRow, 'status' | 'attempts'>): {
  label: string
  className: string
} {
  switch (status) {
    case 'pending':
      return attempts === 0
        ? { label: 'Queued', className: 'bg-gray-100 text-gray-700' }
        : { label: 'Retrying', className: 'bg-amber-50 text-amber-800' }
    case 'succeeded':
      return { label: 'Delivered', className: 'bg-green-50 text-green-800' }
    case 'failed':
      return { label: 'Failed', className: 'bg-red-50 text-red-700' }
    default: {
      const unhandled: never = status
      throw new Error(`Unknown delivery status: ${String(unhandled)}`)
    }
  }
}
