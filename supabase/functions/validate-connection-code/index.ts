// PRUUF Edge Function: validate-connection-code
// Purpose: Validate and create connections using 6-digit codes
//
// This function handles:
// - Code validation (must be active and valid)
// - Self-connection prevention (EC-5.1)
// - Duplicate connection prevention (EC-5.2)
// - Deleted connection reactivation (EC-5.3)
// - Race condition deduplication (EC-5.4)
// - Ping creation for new connections
// - Notification to receiver

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// CORS headers for web/mobile clients
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface ValidateConnectionRequest {
  code: string
  connectingUserId: string
  role: 'sender' | 'receiver'
}

interface ValidateConnectionResponse {
  success: boolean
  connection?: any
  error?: string
  errorCode?: string
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Get request body
    const { code, connectingUserId, role }: ValidateConnectionRequest = await req.json()

    // Validate inputs
    if (!code || !connectingUserId || !role) {
      return new Response(
        JSON.stringify({
          success: false,
          error: 'Missing required parameters: code, connectingUserId, role',
          errorCode: 'INVALID_REQUEST',
        } as ValidateConnectionResponse),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 400,
        }
      )
    }

    // Validate code format (6-digit numeric)
    if (!/^\d{6}$/.test(code)) {
      return new Response(
        JSON.stringify({
          success: false,
          error: 'Invalid code format. Must be 6 digits.',
          errorCode: 'INVALID_CODE_FORMAT',
        } as ValidateConnectionResponse),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 400,
        }
      )
    }

    // Create Supabase client with service role key (bypasses RLS)
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // Look up the unique code to find the receiver
    const { data: uniqueCodeData, error: codeError } = await supabase
      .from('unique_codes')
      .select('*, receiver:receiver_id(id, phone_number, phone_country_code, timezone)')
      .eq('code', code)
      .eq('is_active', true)
      .single()

    if (codeError || !uniqueCodeData) {
      return new Response(
        JSON.stringify({
          success: false,
          error: 'Invalid code. Please check and try again.',
          errorCode: 'INVALID_CODE',
        } as ValidateConnectionResponse),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 404,
        }
      )
    }

    const receiverId = uniqueCodeData.receiver_id

    // Determine sender and receiver based on role
    let senderId: string
    if (role === 'sender') {
      senderId = connectingUserId
      // receiverId is from the code lookup
    } else {
      // Role is receiver - connecting TO a sender
      // In this case, the code would be from sender_profiles invitation_code
      // But per the PRD, receivers use unique_codes which belong to receivers
      // So this shouldn't happen. Return error.
      return new Response(
        JSON.stringify({
          success: false,
          error: 'Invalid role. Receivers do not use unique_codes to connect to senders.',
          errorCode: 'INVALID_ROLE',
        } as ValidateConnectionResponse),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 400,
        }
      )
    }

    // EC-5.1: Prevent self-connection
    if (senderId === receiverId) {
      return new Response(
        JSON.stringify({
          success: false,
          error: 'Cannot connect to your own code',
          errorCode: 'SELF_CONNECTION',
        } as ValidateConnectionResponse),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 400,
        }
      )
    }

    // Check for existing connection (EC-5.2 and EC-5.3)
    const { data: existingConnections, error: existingError } = await supabase
      .from('connections')
      .select('*')
      .eq('sender_id', senderId)
      .eq('receiver_id', receiverId)

    if (existingError) {
      throw existingError
    }

    let connection: any

    if (existingConnections && existingConnections.length > 0) {
      const existing = existingConnections[0]

      if (existing.status === 'deleted') {
        // EC-5.3: Reactivate deleted connection
        const { data: reactivated, error: updateError } = await supabase
          .from('connections')
          .update({
            status: 'active',
            updated_at: new Date().toISOString(),
            deleted_at: null,
          })
          .eq('id', existing.id)
          .select('*, receiver:receiver_id(id, phone_number, phone_country_code, timezone)')
          .single()

        if (updateError) {
          throw updateError
        }

        connection = reactivated

        // Restore pings for reactivated connection
        await supabase
          .from('pings')
          .update({ status: 'pending' })
          .eq('connection_id', existing.id)
          .eq('status', 'deleted')
          .gte('scheduled_time', new Date().toISOString())
      } else {
        // EC-5.2: Connection already exists and is active/paused/pending
        return new Response(
          JSON.stringify({
            success: false,
            error: "You're already connected to this user",
            errorCode: 'DUPLICATE_CONNECTION',
          } as ValidateConnectionResponse),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 409,
          }
        )
      }
    } else {
      // Create new connection with ON CONFLICT handling for EC-5.4
      // Note: The database should have a UNIQUE constraint on (sender_id, receiver_id)
      const { data: newConnection, error: insertError } = await supabase
        .from('connections')
        .insert({
          sender_id: senderId,
          receiver_id: receiverId,
          status: 'active',
          connection_code: code,
        })
        .select('*, receiver:receiver_id(id, phone_number, phone_country_code, timezone)')
        .single()

      if (insertError) {
        // Check if it's a duplicate key error (EC-5.4: race condition)
        if (insertError.code === '23505') {
          // Unique constraint violation - simultaneous connection attempt
          // Fetch the existing connection that was just created
          const { data: existingConn } = await supabase
            .from('connections')
            .select('*, receiver:receiver_id(id, phone_number, phone_country_code, timezone)')
            .eq('sender_id', senderId)
            .eq('receiver_id', receiverId)
            .single()

          if (existingConn) {
            connection = existingConn
          } else {
            throw insertError
          }
        } else {
          throw insertError
        }
      } else {
        connection = newConnection
      }
    }

    // Create today's ping if sender hasn't pinged yet
    await createTodayPingIfNeeded(supabase, connection)

    // Send notification to receiver
    await sendConnectionNotification(supabase, receiverId, senderId)

    // Return success
    return new Response(
      JSON.stringify({
        success: true,
        connection,
      } as ValidateConnectionResponse),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    )
  } catch (error: unknown) {
    console.error('Error validating connection:', error)
    const errorMessage = error instanceof Error ? error.message : 'Internal server error'
    return new Response(
      JSON.stringify({
        success: false,
        error: errorMessage,
        errorCode: 'SERVER_ERROR',
      } as ValidateConnectionResponse),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500,
      }
    )
  }
})

// Helper: Create today's ping for new connection if sender hasn't pinged yet
async function createTodayPingIfNeeded(supabase: any, connection: any) {
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  const tomorrow = new Date(today)
  tomorrow.setDate(tomorrow.getDate() + 1)

  // Check if there's already a ping for this connection today
  const { data: existingPings } = await supabase
    .from('pings')
    .select('id')
    .eq('connection_id', connection.id)
    .gte('scheduled_time', today.toISOString())
    .lt('scheduled_time', tomorrow.toISOString())

  if (existingPings && existingPings.length > 0) {
    return // Ping already exists
  }

  // Get sender's ping time
  const { data: senderProfile } = await supabase
    .from('sender_profiles')
    .select('ping_time')
    .eq('user_id', connection.sender_id)
    .single()

  if (!senderProfile) {
    return // No sender profile found
  }

  // Parse ping time (stored as TIME, e.g., "09:00:00")
  const [hours, minutes] = senderProfile.ping_time.split(':').map(Number)

  // Create scheduled time for today
  const scheduledTime = new Date()
  scheduledTime.setHours(hours, minutes, 0, 0)

  // Calculate deadline (90 minutes after scheduled time)
  const deadlineTime = new Date(scheduledTime)
  deadlineTime.setMinutes(deadlineTime.getMinutes() + 90)

  // Only create ping if deadline is in the future
  if (deadlineTime <= new Date()) {
    return // Deadline has passed
  }

  // Create the ping
  await supabase.from('pings').insert({
    connection_id: connection.id,
    sender_id: connection.sender_id,
    receiver_id: connection.receiver_id,
    scheduled_time: scheduledTime.toISOString(),
    deadline_time: deadlineTime.toISOString(),
    status: 'pending',
  })
}

// Helper: Send notification to receiver about new connection
async function sendConnectionNotification(
  supabase: any,
  receiverId: string,
  senderId: string
) {
  // Get sender's display name
  const { data: sender } = await supabase
    .from('users')
    .select('phone_number')
    .eq('id', senderId)
    .single()

  const senderName = sender?.phone_number || 'Someone'

  // Get receiver's device token
  const { data: receiver } = await supabase
    .from('users')
    .select('device_token')
    .eq('id', receiverId)
    .single()

  // Create notification record
  await supabase.from('notifications').insert({
    user_id: receiverId,
    type: 'connection_request',
    title: 'New Connection',
    body: `${senderName} is now sending you pings`,
    delivery_status: 'sent',
  })

  // If receiver has a device token, send push notification
  // This would typically call the send-apns-notification function
  if (receiver?.device_token) {
    // For now, just log it - actual push would be implemented separately
    console.log(
      `Would send push notification to device token: ${receiver.device_token}`
    )
  }
}
