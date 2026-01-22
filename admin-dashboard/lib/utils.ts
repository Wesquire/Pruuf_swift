import { type ClassValue, clsx } from "clsx"
import { twMerge } from "tailwind-merge"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function formatCurrency(amount: number): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
  }).format(amount)
}

export function formatPercent(value: number): string {
  return `${(value * 100).toFixed(2)}%`
}

export function formatNumber(value: number): string {
  return new Intl.NumberFormat('en-US').format(value)
}

export function formatDate(date: string | Date): string {
  return new Intl.DateTimeFormat('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(date))
}

export function formatRelativeTime(date: string | Date): string {
  const now = new Date()
  const then = new Date(date)
  const diffMs = now.getTime() - then.getTime()
  const diffMins = Math.floor(diffMs / 60000)
  const diffHours = Math.floor(diffMins / 60)
  const diffDays = Math.floor(diffHours / 24)

  if (diffMins < 1) return 'Just now'
  if (diffMins < 60) return `${diffMins}m ago`
  if (diffHours < 24) return `${diffHours}h ago`
  if (diffDays < 7) return `${diffDays}d ago`
  return formatDate(date)
}

export function getHealthStatusColor(status: 'healthy' | 'degraded' | 'critical'): string {
  switch (status) {
    case 'healthy':
      return 'text-green-600'
    case 'degraded':
      return 'text-yellow-600'
    case 'critical':
      return 'text-red-600'
    default:
      return 'text-gray-600'
  }
}

export function getHealthStatusBgColor(status: 'healthy' | 'degraded' | 'critical'): string {
  switch (status) {
    case 'healthy':
      return 'bg-green-100'
    case 'degraded':
      return 'bg-yellow-100'
    case 'critical':
      return 'bg-red-100'
    default:
      return 'bg-gray-100'
  }
}
