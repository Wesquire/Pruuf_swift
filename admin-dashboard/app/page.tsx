'use client'

import { useEffect, useState } from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import {
  getUserMetrics,
  getConnectionAnalytics,
  getPingAnalytics,
  getSubscriptionMetrics,
  getSystemHealth,
  searchUsersByPhone,
  getMissedPingAlerts,
  getPaymentFailures,
  getEdgeFunctionMetrics,
  getCronJobStats,
  type UserMetrics,
  type ConnectionAnalytics,
  type PingAnalytics,
  type SubscriptionMetrics,
  type SystemHealth,
} from '@/lib/supabase'
import {
  formatCurrency,
  formatPercent,
  formatNumber,
  formatDate,
  formatRelativeTime,
  getHealthStatusColor,
  getHealthStatusBgColor,
} from '@/lib/utils'
import {
  Users,
  Activity,
  DollarSign,
  Bell,
  TrendingUp,
  AlertTriangle,
  CheckCircle,
  Server,
  Search,
} from 'lucide-react'

export default function AdminDashboard() {
  const [userMetrics, setUserMetrics] = useState<UserMetrics | null>(null)
  const [connectionAnalytics, setConnectionAnalytics] = useState<ConnectionAnalytics | null>(null)
  const [pingAnalytics, setPingAnalytics] = useState<PingAnalytics | null>(null)
  const [subscriptionMetrics, setSubscriptionMetrics] = useState<SubscriptionMetrics | null>(null)
  const [systemHealth, setSystemHealth] = useState<SystemHealth | null>(null)
  const [loading, setLoading] = useState(true)
  const [searchPhone, setSearchPhone] = useState('')
  const [searchResults, setSearchResults] = useState<any[]>([])

  useEffect(() => {
    loadDashboardData()
  }, [])

  async function loadDashboardData() {
    try {
      setLoading(true)
      const [users, connections, pings, subscriptions, health] = await Promise.all([
        getUserMetrics(),
        getConnectionAnalytics(),
        getPingAnalytics(),
        getSubscriptionMetrics(),
        getSystemHealth(),
      ])
      setUserMetrics(users)
      setConnectionAnalytics(connections)
      setPingAnalytics(pings)
      setSubscriptionMetrics(subscriptions)
      setSystemHealth(health)
    } catch (error) {
      console.error('Error loading dashboard:', error)
    } finally {
      setLoading(false)
    }
  }

  async function handleSearch() {
    if (!searchPhone) return
    try {
      const results = await searchUsersByPhone(searchPhone)
      setSearchResults(Array.isArray(results) ? results : [])
    } catch (error) {
      console.error('Search error:', error)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary mx-auto mb-4"></div>
          <p className="text-muted-foreground">Loading dashboard...</p>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <header className="bg-white border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <div className="flex items-center justify-between">
            <div>
              <h1 className="text-2xl font-bold text-gray-900">PRUUF Admin Dashboard</h1>
              <p className="text-sm text-gray-500">System monitoring and management</p>
            </div>
            <Button onClick={loadDashboardData} variant="outline">
              Refresh Data
            </Button>
          </div>
        </div>
      </header>

      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <Tabs defaultValue="overview" className="space-y-6">
          <TabsList>
            <TabsTrigger value="overview">Overview</TabsTrigger>
            <TabsTrigger value="users">User Management</TabsTrigger>
            <TabsTrigger value="pings">Ping Analytics</TabsTrigger>
            <TabsTrigger value="subscriptions">Subscriptions</TabsTrigger>
            <TabsTrigger value="system">System Health</TabsTrigger>
          </TabsList>

          {/* Overview Tab */}
          <TabsContent value="overview" className="space-y-6">
            {/* System Health Status */}
            {systemHealth && (
              <Card>
                <CardHeader>
                  <div className="flex items-center justify-between">
                    <div>
                      <CardTitle>System Health</CardTitle>
                      <CardDescription>Current system status</CardDescription>
                    </div>
                    <Badge
                      className={getHealthStatusBgColor(systemHealth.health_status)}
                    >
                      <span className={getHealthStatusColor(systemHealth.health_status)}>
                        {systemHealth.health_status.toUpperCase()}
                      </span>
                    </Badge>
                  </div>
                </CardHeader>
                <CardContent>
                  <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
                    <div>
                      <p className="text-sm text-muted-foreground">Active Sessions</p>
                      <p className="text-2xl font-bold">{systemHealth.active_user_sessions}</p>
                    </div>
                    <div>
                      <p className="text-sm text-muted-foreground">Pending Pings</p>
                      <p className="text-2xl font-bold">{systemHealth.pending_pings}</p>
                    </div>
                    <div>
                      <p className="text-sm text-muted-foreground">Notification Delivery</p>
                      <p className="text-2xl font-bold">
                        {formatPercent(systemHealth.push_notification_delivery_rate)}
                      </p>
                    </div>
                    <div>
                      <p className="text-sm text-muted-foreground">Avg Query Time</p>
                      <p className="text-2xl font-bold">{systemHealth.average_query_time_ms}ms</p>
                    </div>
                  </div>
                </CardContent>
              </Card>
            )}

            {/* Key Metrics Row */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
              {/* Users */}
              {userMetrics && (
                <Card>
                  <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                    <CardTitle className="text-sm font-medium">Total Users</CardTitle>
                    <Users className="h-4 w-4 text-muted-foreground" />
                  </CardHeader>
                  <CardContent>
                    <div className="text-2xl font-bold">{formatNumber(userMetrics.total_users)}</div>
                    <p className="text-xs text-muted-foreground">
                      +{userMetrics.new_signups_this_week} this week
                    </p>
                  </CardContent>
                </Card>
              )}

              {/* Connections */}
              {connectionAnalytics && (
                <Card>
                  <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                    <CardTitle className="text-sm font-medium">Active Connections</CardTitle>
                    <Activity className="h-4 w-4 text-muted-foreground" />
                  </CardHeader>
                  <CardContent>
                    <div className="text-2xl font-bold">
                      {formatNumber(connectionAnalytics.active_connections)}
                    </div>
                    <p className="text-xs text-muted-foreground">
                      {formatPercent(connectionAnalytics.growth_percentage / 100)} growth
                    </p>
                  </CardContent>
                </Card>
              )}

              {/* Revenue */}
              {subscriptionMetrics && (
                <Card>
                  <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                    <CardTitle className="text-sm font-medium">MRR</CardTitle>
                    <DollarSign className="h-4 w-4 text-muted-foreground" />
                  </CardHeader>
                  <CardContent>
                    <div className="text-2xl font-bold">
                      {formatCurrency(subscriptionMetrics.monthly_recurring_revenue)}
                    </div>
                    <p className="text-xs text-muted-foreground">
                      {subscriptionMetrics.active_subscriptions} active subscriptions
                    </p>
                  </CardContent>
                </Card>
              )}

              {/* Pings */}
              {pingAnalytics && (
                <Card>
                  <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                    <CardTitle className="text-sm font-medium">Pings Today</CardTitle>
                    <Bell className="h-4 w-4 text-muted-foreground" />
                  </CardHeader>
                  <CardContent>
                    <div className="text-2xl font-bold">
                      {formatNumber(pingAnalytics.total_pings_today)}
                    </div>
                    <p className="text-xs text-muted-foreground">
                      {formatPercent(pingAnalytics.completion_rate_on_time)} on-time
                    </p>
                  </CardContent>
                </Card>
              )}
            </div>

            {/* User Breakdown */}
            {userMetrics && (
              <Card>
                <CardHeader>
                  <CardTitle>User Distribution</CardTitle>
                  <CardDescription>Users by role and activity</CardDescription>
                </CardHeader>
                <CardContent>
                  <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                    <div>
                      <p className="text-sm text-muted-foreground mb-2">By Role</p>
                      <div className="space-y-2">
                        <div className="flex justify-between">
                          <span className="text-sm">Senders</span>
                          <span className="text-sm font-medium">{userMetrics.sender_count}</span>
                        </div>
                        <div className="flex justify-between">
                          <span className="text-sm">Receivers</span>
                          <span className="text-sm font-medium">{userMetrics.receiver_count}</span>
                        </div>
                        <div className="flex justify-between">
                          <span className="text-sm">Both</span>
                          <span className="text-sm font-medium">{userMetrics.both_role_count}</span>
                        </div>
                      </div>
                    </div>
                    <div>
                      <p className="text-sm text-muted-foreground mb-2">Activity (Last 30 Days)</p>
                      <div className="space-y-2">
                        <div className="flex justify-between">
                          <span className="text-sm">Active Users</span>
                          <span className="text-sm font-medium">
                            {userMetrics.active_users_last_30_days}
                          </span>
                        </div>
                        <div className="flex justify-between">
                          <span className="text-sm">Activity Rate</span>
                          <span className="text-sm font-medium">
                            {formatPercent(
                              userMetrics.active_users_last_30_days / userMetrics.total_users
                            )}
                          </span>
                        </div>
                      </div>
                    </div>
                    <div>
                      <p className="text-sm text-muted-foreground mb-2">New Signups</p>
                      <div className="space-y-2">
                        <div className="flex justify-between">
                          <span className="text-sm">Today</span>
                          <span className="text-sm font-medium">{userMetrics.new_signups_today}</span>
                        </div>
                        <div className="flex justify-between">
                          <span className="text-sm">This Week</span>
                          <span className="text-sm font-medium">
                            {userMetrics.new_signups_this_week}
                          </span>
                        </div>
                        <div className="flex justify-between">
                          <span className="text-sm">This Month</span>
                          <span className="text-sm font-medium">
                            {userMetrics.new_signups_this_month}
                          </span>
                        </div>
                      </div>
                    </div>
                  </div>
                </CardContent>
              </Card>
            )}

            {/* Ping Performance */}
            {pingAnalytics && (
              <Card>
                <CardHeader>
                  <CardTitle>Ping Performance</CardTitle>
                  <CardDescription>Completion rates and streaks</CardDescription>
                </CardHeader>
                <CardContent>
                  <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
                    <div>
                      <p className="text-sm text-muted-foreground mb-2">This Month</p>
                      <p className="text-2xl font-bold">{formatNumber(pingAnalytics.total_pings_this_month)}</p>
                      <p className="text-xs text-muted-foreground">Total pings</p>
                    </div>
                    <div>
                      <div className="flex items-center mb-2">
                        <CheckCircle className="h-4 w-4 text-green-600 mr-2" />
                        <p className="text-sm text-muted-foreground">On-Time</p>
                      </div>
                      <p className="text-2xl font-bold text-green-600">
                        {formatPercent(pingAnalytics.completion_rate_on_time)}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        {formatNumber(pingAnalytics.on_time_count)} pings
                      </p>
                    </div>
                    <div>
                      <div className="flex items-center mb-2">
                        <AlertTriangle className="h-4 w-4 text-yellow-600 mr-2" />
                        <p className="text-sm text-muted-foreground">Late</p>
                      </div>
                      <p className="text-2xl font-bold text-yellow-600">
                        {formatPercent(pingAnalytics.completion_rate_late)}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        {formatNumber(pingAnalytics.late_count)} pings
                      </p>
                    </div>
                    <div>
                      <div className="flex items-center mb-2">
                        <AlertTriangle className="h-4 w-4 text-red-600 mr-2" />
                        <p className="text-sm text-muted-foreground">Missed</p>
                      </div>
                      <p className="text-2xl font-bold text-red-600">
                        {formatPercent(pingAnalytics.missed_rate)}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        {formatNumber(pingAnalytics.missed_count)} pings
                      </p>
                    </div>
                  </div>
                </CardContent>
              </Card>
            )}
          </TabsContent>

          {/* User Management Tab */}
          <TabsContent value="users" className="space-y-6">
            <Card>
              <CardHeader>
                <CardTitle>Search Users</CardTitle>
                <CardDescription>Search by phone number</CardDescription>
              </CardHeader>
              <CardContent>
                <div className="flex gap-2">
                  <Input
                    placeholder="Enter phone number..."
                    value={searchPhone}
                    onChange={(e) => setSearchPhone(e.target.value)}
                    onKeyDown={(e) => e.key === 'Enter' && handleSearch()}
                  />
                  <Button onClick={handleSearch}>
                    <Search className="h-4 w-4 mr-2" />
                    Search
                  </Button>
                </div>

                {searchResults.length > 0 && (
                  <div className="mt-6 space-y-2">
                    {searchResults.map((user: any) => (
                      <div key={user.id} className="border rounded-lg p-4">
                        <div className="flex justify-between items-start">
                          <div>
                            <p className="font-medium">{user.phone_number}</p>
                            <p className="text-sm text-muted-foreground">
                              Role: {user.primary_role} • Joined: {formatDate(user.created_at)}
                            </p>
                            <p className="text-sm text-muted-foreground">
                              Connections: {user.connection_count} • Pings: {user.ping_count}
                            </p>
                          </div>
                          <div className="flex gap-2">
                            {user.subscription_status && (
                              <Badge>{user.subscription_status}</Badge>
                            )}
                            {user.is_active ? (
                              <Badge variant="default">Active</Badge>
                            ) : (
                              <Badge variant="destructive">Inactive</Badge>
                            )}
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </CardContent>
            </Card>
          </TabsContent>

          {/* Ping Analytics Tab */}
          <TabsContent value="pings" className="space-y-6">
            {pingAnalytics && (
              <>
                <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                  <Card>
                    <CardHeader>
                      <CardTitle>Average Completion Time</CardTitle>
                    </CardHeader>
                    <CardContent>
                      <p className="text-3xl font-bold">
                        {pingAnalytics.average_completion_time_minutes.toFixed(1)} min
                      </p>
                    </CardContent>
                  </Card>
                  <Card>
                    <CardHeader>
                      <CardTitle>Longest Streak</CardTitle>
                    </CardHeader>
                    <CardContent>
                      <p className="text-3xl font-bold">{pingAnalytics.longest_streak} days</p>
                    </CardContent>
                  </Card>
                  <Card>
                    <CardHeader>
                      <CardTitle>Average Streak</CardTitle>
                    </CardHeader>
                    <CardContent>
                      <p className="text-3xl font-bold">
                        {pingAnalytics.average_streak.toFixed(1)} days
                      </p>
                    </CardContent>
                  </Card>
                </div>
              </>
            )}
          </TabsContent>

          {/* Subscriptions Tab */}
          <TabsContent value="subscriptions" className="space-y-6">
            {subscriptionMetrics && (
              <>
                <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                  <Card>
                    <CardHeader>
                      <CardTitle>MRR</CardTitle>
                      <CardDescription>Monthly Recurring Revenue</CardDescription>
                    </CardHeader>
                    <CardContent>
                      <p className="text-3xl font-bold">
                        {formatCurrency(subscriptionMetrics.monthly_recurring_revenue)}
                      </p>
                      <p className="text-sm text-muted-foreground mt-2">
                        ARPU: {formatCurrency(subscriptionMetrics.average_revenue_per_user)}
                      </p>
                    </CardContent>
                  </Card>
                  <Card>
                    <CardHeader>
                      <CardTitle>Conversion Rate</CardTitle>
                      <CardDescription>Trial to Paid</CardDescription>
                    </CardHeader>
                    <CardContent>
                      <p className="text-3xl font-bold">
                        {formatPercent(subscriptionMetrics.trial_conversion_rate)}
                      </p>
                      <p className="text-sm text-muted-foreground mt-2">
                        Trial users: {subscriptionMetrics.trial_users}
                      </p>
                    </CardContent>
                  </Card>
                  <Card>
                    <CardHeader>
                      <CardTitle>Churn Rate</CardTitle>
                      <CardDescription>Monthly churn</CardDescription>
                    </CardHeader>
                    <CardContent>
                      <p className="text-3xl font-bold">
                        {formatPercent(subscriptionMetrics.churn_rate)}
                      </p>
                      <p className="text-sm text-muted-foreground mt-2">
                        LTV: {formatCurrency(subscriptionMetrics.lifetime_value)}
                      </p>
                    </CardContent>
                  </Card>
                </div>

                <Card>
                  <CardHeader>
                    <CardTitle>Subscription Breakdown</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
                      <div>
                        <p className="text-sm text-muted-foreground">Active</p>
                        <p className="text-2xl font-bold text-green-600">
                          {subscriptionMetrics.active_subscriptions}
                        </p>
                      </div>
                      <div>
                        <p className="text-sm text-muted-foreground">Trial</p>
                        <p className="text-2xl font-bold">{subscriptionMetrics.trial_users}</p>
                      </div>
                      <div>
                        <p className="text-sm text-muted-foreground">Past Due</p>
                        <p className="text-2xl font-bold text-yellow-600">
                          {subscriptionMetrics.past_due_subscriptions}
                        </p>
                      </div>
                      <div>
                        <p className="text-sm text-muted-foreground">Canceled</p>
                        <p className="text-2xl font-bold text-red-600">
                          {subscriptionMetrics.canceled_subscriptions}
                        </p>
                      </div>
                      <div>
                        <p className="text-sm text-muted-foreground">Expired</p>
                        <p className="text-2xl font-bold text-gray-600">
                          {subscriptionMetrics.expired_subscriptions}
                        </p>
                      </div>
                    </div>
                  </CardContent>
                </Card>

                <Card>
                  <CardHeader>
                    <CardTitle>Payment Issues</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                      <div>
                        <p className="text-sm text-muted-foreground">Payment Failures</p>
                        <p className="text-2xl font-bold">
                          {subscriptionMetrics.payment_failures_this_month}
                        </p>
                      </div>
                      <div>
                        <p className="text-sm text-muted-foreground">Refunds</p>
                        <p className="text-2xl font-bold">{subscriptionMetrics.refunds_this_month}</p>
                      </div>
                      <div>
                        <p className="text-sm text-muted-foreground">Chargebacks</p>
                        <p className="text-2xl font-bold">
                          {subscriptionMetrics.chargebacks_this_month}
                        </p>
                      </div>
                    </div>
                  </CardContent>
                </Card>
              </>
            )}
          </TabsContent>

          {/* System Health Tab */}
          <TabsContent value="system" className="space-y-6">
            {systemHealth && (
              <>
                <Card>
                  <CardHeader>
                    <CardTitle>Database & API Performance</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                      <div>
                        <p className="text-sm text-muted-foreground">Connection Pool Usage</p>
                        <p className="text-2xl font-bold">
                          {formatPercent(systemHealth.database_connection_pool_usage)}
                        </p>
                      </div>
                      <div>
                        <p className="text-sm text-muted-foreground">Avg Query Time</p>
                        <p className="text-2xl font-bold">{systemHealth.average_query_time_ms}ms</p>
                      </div>
                      <div>
                        <p className="text-sm text-muted-foreground">API Error Rate (24h)</p>
                        <p className="text-2xl font-bold">
                          {formatPercent(systemHealth.api_error_rate_last_24h)}
                        </p>
                      </div>
                    </div>
                  </CardContent>
                </Card>

                <Card>
                  <CardHeader>
                    <CardTitle>Notifications & Jobs</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                      <div>
                        <p className="text-sm text-muted-foreground">Push Notification Delivery</p>
                        <p className="text-2xl font-bold text-green-600">
                          {formatPercent(systemHealth.push_notification_delivery_rate)}
                        </p>
                      </div>
                      <div>
                        <p className="text-sm text-muted-foreground">Cron Job Success Rate</p>
                        <p className="text-2xl font-bold text-green-600">
                          {formatPercent(systemHealth.cron_job_success_rate)}
                        </p>
                      </div>
                    </div>
                  </CardContent>
                </Card>

                <Card>
                  <CardHeader>
                    <CardTitle>Storage</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <p className="text-sm text-muted-foreground">Total Storage Used</p>
                    <p className="text-2xl font-bold">{systemHealth.storage_usage_formatted}</p>
                  </CardContent>
                </Card>
              </>
            )}
          </TabsContent>
        </Tabs>
      </main>
    </div>
  )
}
