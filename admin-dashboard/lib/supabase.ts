import { createClient } from '@supabase/supabase-js'

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!

export const supabase = createClient(supabaseUrl, supabaseAnonKey)

// Types
export interface AdminUser {
  id: string
  email: string
  role: string
  is_active: boolean
  permissions: Record<string, boolean>
}

export interface UserMetrics {
  total_users: number
  active_users_last_7_days: number
  active_users_last_30_days: number
  new_signups_today: number
  new_signups_this_week: number
  new_signups_this_month: number
  sender_count: number
  receiver_count: number
  both_role_count: number
}

export interface ConnectionAnalytics {
  total_connections: number
  active_connections: number
  paused_connections: number
  deleted_connections: number
  average_connections_per_user: number
  connection_growth_this_month: number
  connection_growth_last_month: number
  growth_percentage: number
}

export interface PingAnalytics {
  total_pings_today: number
  total_pings_this_week: number
  total_pings_this_month: number
  on_time_count: number
  late_count: number
  missed_count: number
  on_break_count: number
  completion_rate_on_time: number
  completion_rate_late: number
  missed_rate: number
  average_completion_time_minutes: number
  longest_streak: number
  average_streak: number
}

export interface SubscriptionMetrics {
  monthly_recurring_revenue: number
  active_subscriptions: number
  trial_users: number
  past_due_subscriptions: number
  canceled_subscriptions: number
  expired_subscriptions: number
  trial_conversion_rate: number
  churn_rate: number
  average_revenue_per_user: number
  lifetime_value: number
  payment_failures_this_month: number
  refunds_this_month: number
  chargebacks_this_month: number
}

export interface SystemHealth {
  database_connection_pool_usage: number
  average_query_time_ms: number
  api_error_rate_last_24h: number
  push_notification_delivery_rate: number
  cron_job_success_rate: number
  storage_usage_bytes: number
  storage_usage_formatted: string
  active_user_sessions: number
  pending_pings: number
  health_status: 'healthy' | 'degraded' | 'critical'
}

// Admin API functions
export async function getUserMetrics(): Promise<UserMetrics> {
  const { data, error } = await supabase.rpc('get_admin_user_metrics')
  if (error) throw error
  return data
}

export async function getConnectionAnalytics(): Promise<ConnectionAnalytics> {
  const { data, error } = await supabase.rpc('get_admin_connection_analytics')
  if (error) throw error
  return data
}

export async function getPingAnalytics(): Promise<PingAnalytics> {
  const { data, error } = await supabase.rpc('get_admin_ping_analytics')
  if (error) throw error
  return data
}

export async function getSubscriptionMetrics(): Promise<SubscriptionMetrics> {
  const { data, error } = await supabase.rpc('get_admin_subscription_metrics')
  if (error) throw error
  return data
}

export async function getSystemHealth(): Promise<SystemHealth> {
  const { data, error } = await supabase.rpc('get_admin_system_health')
  if (error) throw error
  return data
}

export async function searchUsersByPhone(phoneNumber: string) {
  const { data, error } = await supabase.rpc('admin_search_users_by_phone', {
    search_phone: phoneNumber
  })
  if (error) throw error
  return data
}

export async function getUserDetails(userId: string) {
  const { data, error } = await supabase.rpc('admin_get_user_details', {
    target_user_id: userId
  })
  if (error) throw error
  return data
}

export async function deactivateUser(userId: string, reason: string) {
  const { error } = await supabase.rpc('admin_deactivate_user', {
    target_user_id: userId,
    deactivation_reason: reason
  })
  if (error) throw error
}

export async function reactivateUser(userId: string) {
  const { error } = await supabase.rpc('admin_reactivate_user', {
    target_user_id: userId
  })
  if (error) throw error
}

export async function updateSubscription(
  userId: string,
  newStatus: string,
  newEndDate?: string
) {
  const { error } = await supabase.rpc('admin_update_subscription', {
    target_user_id: userId,
    new_status: newStatus,
    new_end_date: newEndDate || null
  })
  if (error) throw error
}

export async function getTopUsersByConnections(limit: number = 10) {
  const { data, error } = await supabase.rpc('admin_get_top_users_by_connections', {
    result_limit: limit
  })
  if (error) throw error
  return data
}

export async function getMissedPingAlerts(limit: number = 50) {
  const { data, error } = await supabase.rpc('admin_get_missed_ping_alerts', {
    result_limit: limit
  })
  if (error) throw error
  return data
}

export async function getPaymentFailures(limit: number = 50) {
  const { data, error } = await supabase.rpc('admin_get_payment_failures', {
    result_limit: limit
  })
  if (error) throw error
  return data
}

export async function getEdgeFunctionMetrics() {
  const { data, error } = await supabase.rpc('admin_get_edge_function_metrics')
  if (error) throw error
  return data
}

export async function getCronJobStats() {
  const { data, error } = await supabase.rpc('admin_get_cron_job_stats')
  if (error) throw error
  return data
}

export async function sendTestNotification(
  userId: string,
  title: string,
  body: string
) {
  const { error } = await supabase.rpc('admin_send_test_notification', {
    target_user_id: userId,
    notification_title: title,
    notification_body: body
  })
  if (error) throw error
}

export async function cancelSubscription(userId: string, reason: string) {
  const { error } = await supabase.rpc('admin_cancel_subscription', {
    target_user_id: userId,
    cancellation_reason: reason
  })
  if (error) throw error
}
