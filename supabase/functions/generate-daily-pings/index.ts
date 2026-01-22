// Edge Function: generate-daily-pings
// Scheduled function to create daily ping records for all active sender/receiver connections
// Runs at midnight UTC via cron: 0 0 * * *
// Phase 6 Section 6.1: Daily Ping Generation

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface SenderProfile {
  user_id: string;
  ping_time: string; // TIME format HH:MM:SS in sender's local time
  ping_enabled: boolean;
}

interface UserTimezone {
  id: string;
  timezone: string;
}

interface Connection {
  id: string;
  sender_id: string;
  receiver_id: string;
  status: string;
}

interface Break {
  sender_id: string;
  start_date: string;
  end_date: string;
  status: string;
}

interface ReceiverProfile {
  user_id: string;
  subscription_status: string;
  trial_end_date: string | null;
  subscription_end_date: string | null;
  updated_at: string | null;
}

interface PingRecord {
  connection_id: string;
  sender_id: string;
  receiver_id: string;
  scheduled_time: string;
  deadline_time: string;
  status: string;
}

// Section 9.5: Check if receiver subscription allows ping generation
// Returns true if pings should be generated, false if they should be skipped
// - active/trial (not expired): generate pings
// - past_due: 3-day grace period, then skip
// - expired/canceled: skip pings
const GRACE_PERIOD_DAYS = 3;

function isReceiverSubscriptionActive(receiver: ReceiverProfile): boolean {
  const now = new Date();
  const status = receiver.subscription_status;

  // Active subscription
  if (status === "active") {
    // Check if subscription has expired
    if (receiver.subscription_end_date) {
      const endDate = new Date(receiver.subscription_end_date);
      return endDate > now;
    }
    return true;
  }

  // Trial subscription
  if (status === "trial") {
    if (receiver.trial_end_date) {
      const trialEnd = new Date(receiver.trial_end_date);
      return trialEnd > now;
    }
    // If no trial end date, assume trial is valid
    return true;
  }

  // Section 9.5: past_due with 3-day grace period
  if (status === "past_due") {
    if (receiver.updated_at) {
      const updatedAt = new Date(receiver.updated_at);
      const daysSincePastDue = Math.floor(
        (now.getTime() - updatedAt.getTime()) / (1000 * 60 * 60 * 24)
      );
      // Allow pings during grace period
      return daysSincePastDue <= GRACE_PERIOD_DAYS;
    }
    // No updated_at, default to skip
    return false;
  }

  // Expired or canceled - skip pings
  return false;
}

// Check if sender is on break for a given date
// EC-7.3: If break ends today, tomorrow's ping reverts to 'pending'
// This is handled by the date range check - if the check date is after end_date,
// the sender is NOT on break, so tomorrow's ping status = 'pending'
function isSenderOnBreak(breaks: Break[], date: Date): boolean {
  const dateStr = date.toISOString().split("T")[0];

  return breaks.some((breakRecord) => {
    const isActive = breakRecord.status === "scheduled" || breakRecord.status === "active";
    // Check if date falls within break range (inclusive of start and end dates)
    // When break ends today: today = on_break, tomorrow = pending (outside range)
    const withinRange = dateStr >= breakRecord.start_date && dateStr <= breakRecord.end_date;
    return isActive && withinRange;
  });
}

// Calculate scheduled time for a sender based on their ping_time and timezone
// ping_time is stored as local time (HH:MM:SS), we convert to UTC using sender's timezone
// Phase 6.1: "9 AM local" means 9 AM wherever sender currently is
function calculateScheduledTime(pingTimeLocal: string, targetDate: Date, senderTimezone: string): Date {
  const [hours, minutes, seconds] = pingTimeLocal.split(":").map(Number);

  // Create a date string in the sender's local timezone
  const year = targetDate.getUTCFullYear();
  const month = String(targetDate.getUTCMonth() + 1).padStart(2, '0');
  const day = String(targetDate.getUTCDate()).padStart(2, '0');
  const timeStr = `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}:${String(seconds || 0).padStart(2, '0')}`;

  // Format: YYYY-MM-DDTHH:MM:SS in sender's timezone
  const localDateTimeStr = `${year}-${month}-${day}T${timeStr}`;

  // Use Intl.DateTimeFormat to convert from sender's timezone to UTC
  // This handles DST automatically
  try {
    // Create a formatter for the sender's timezone
    const formatter = new Intl.DateTimeFormat('en-US', {
      timeZone: senderTimezone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hour12: false
    });

    // Parse the local time and convert to UTC
    // We need to find the UTC time that, when converted to sender's timezone, gives the desired local time
    // Use binary search or iteration to find the correct UTC time
    const targetLocalTime = hours * 60 + minutes;
    let utcDate = new Date(Date.UTC(year, targetDate.getUTCMonth(), targetDate.getUTCDate(), hours, minutes, seconds || 0));

    // Get the timezone offset in minutes
    // We compare the local time to UTC time to find the offset
    const testDate = new Date(utcDate);
    const localTimeStr = testDate.toLocaleTimeString('en-US', {
      timeZone: senderTimezone,
      hour12: false,
      hour: '2-digit',
      minute: '2-digit'
    });
    const [localHours, localMinutes] = localTimeStr.split(':').map(Number);
    const actualLocalTime = localHours * 60 + localMinutes;

    // Adjust UTC time to match desired local time
    const offsetMinutes = actualLocalTime - targetLocalTime;
    utcDate = new Date(utcDate.getTime() - offsetMinutes * 60 * 1000);

    return utcDate;
  } catch (error) {
    // Fallback: treat ping_time as UTC if timezone conversion fails
    console.warn(`Timezone conversion failed for ${senderTimezone}, falling back to UTC:`, error);
    const scheduled = new Date(targetDate);
    scheduled.setUTCHours(hours, minutes, seconds || 0, 0);
    return scheduled;
  }
}

// Calculate deadline as scheduled_time + 90 minutes
function calculateDeadline(scheduledTime: Date): Date {
  const deadline = new Date(scheduledTime);
  deadline.setMinutes(deadline.getMinutes() + 90);
  return deadline;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    // Get target date - today in UTC
    const now = new Date();
    const today = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
    const todayStr = today.toISOString().split("T")[0];

    console.log(`[generate-daily-pings] Starting for date: ${todayStr}`);

    // 1. Get all active connections
    // EC-7.4: Only active connections get pings. Paused connections are excluded.
    // If connection is paused during a break, no pings are generated (connection pause takes precedence)
    const { data: connections, error: connectionsError } = await supabaseClient
      .from("connections")
      .select("id, sender_id, receiver_id, status")
      .eq("status", "active");

    if (connectionsError) {
      throw new Error(`Failed to fetch connections: ${connectionsError.message}`);
    }

    if (!connections || connections.length === 0) {
      console.log("[generate-daily-pings] No active connections found");
      return new Response(
        JSON.stringify({
          success: true,
          message: "No active connections to process",
          date: todayStr,
          pings_created: 0,
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 200,
        }
      );
    }

    console.log(`[generate-daily-pings] Found ${connections.length} active connections`);

    // 2. Get all sender profiles with ping times
    const senderIds = [...new Set(connections.map((c: Connection) => c.sender_id))];
    const { data: senderProfiles, error: senderError } = await supabaseClient
      .from("sender_profiles")
      .select("user_id, ping_time, ping_enabled")
      .in("user_id", senderIds);

    if (senderError) {
      throw new Error(`Failed to fetch sender profiles: ${senderError.message}`);
    }

    // Create map for quick lookup
    const senderProfileMap = new Map<string, SenderProfile>();
    (senderProfiles || []).forEach((sp: SenderProfile) => {
      senderProfileMap.set(sp.user_id, sp);
    });

    // 2b. Get all sender timezones for timezone conversion
    // Phase 6.1: "9 AM local" means 9 AM wherever sender currently is
    const { data: senderUsers, error: senderUsersError } = await supabaseClient
      .from("users")
      .select("id, timezone")
      .in("id", senderIds);

    if (senderUsersError) {
      throw new Error(`Failed to fetch sender timezones: ${senderUsersError.message}`);
    }

    // Create timezone map for quick lookup
    const senderTimezoneMap = new Map<string, string>();
    (senderUsers || []).forEach((u: UserTimezone) => {
      senderTimezoneMap.set(u.id, u.timezone || 'UTC');
    });

    // 3. Get all receiver profiles for subscription status check
    // Section 9.5: Include updated_at for past_due grace period calculation
    const receiverIds = [...new Set(connections.map((c: Connection) => c.receiver_id))];
    const { data: receiverProfiles, error: receiverError } = await supabaseClient
      .from("receiver_profiles")
      .select("user_id, subscription_status, trial_end_date, subscription_end_date, updated_at")
      .in("user_id", receiverIds);

    if (receiverError) {
      throw new Error(`Failed to fetch receiver profiles: ${receiverError.message}`);
    }

    // Create map for quick lookup
    const receiverProfileMap = new Map<string, ReceiverProfile>();
    (receiverProfiles || []).forEach((rp: ReceiverProfile) => {
      receiverProfileMap.set(rp.user_id, rp);
    });

    // 4. Get all active breaks for today
    const { data: breaks, error: breaksError } = await supabaseClient
      .from("breaks")
      .select("sender_id, start_date, end_date, status")
      .in("sender_id", senderIds)
      .in("status", ["scheduled", "active"])
      .lte("start_date", todayStr)
      .gte("end_date", todayStr);

    if (breaksError) {
      throw new Error(`Failed to fetch breaks: ${breaksError.message}`);
    }

    // Group breaks by sender
    const senderBreaksMap = new Map<string, Break[]>();
    (breaks || []).forEach((b: Break) => {
      const existing = senderBreaksMap.get(b.sender_id) || [];
      existing.push(b);
      senderBreaksMap.set(b.sender_id, existing);
    });

    // 5. Check for existing pings for today to avoid duplicates
    const connectionIds = connections.map((c: Connection) => c.id);
    const { data: existingPings, error: existingError } = await supabaseClient
      .from("pings")
      .select("connection_id")
      .in("connection_id", connectionIds)
      .gte("scheduled_time", `${todayStr}T00:00:00Z`)
      .lt("scheduled_time", `${todayStr}T23:59:59Z`);

    if (existingError) {
      throw new Error(`Failed to check existing pings: ${existingError.message}`);
    }

    const existingPingConnectionIds = new Set(
      (existingPings || []).map((p: { connection_id: string }) => p.connection_id)
    );

    // 6. Create ping records for each connection
    const pingsToCreate: PingRecord[] = [];
    const skipped: { reason: string; connection_id: string }[] = [];

    for (const connection of connections as Connection[]) {
      // Skip if ping already exists for today
      if (existingPingConnectionIds.has(connection.id)) {
        skipped.push({ reason: "ping_already_exists", connection_id: connection.id });
        continue;
      }

      // Get sender profile
      const senderProfile = senderProfileMap.get(connection.sender_id);
      if (!senderProfile) {
        skipped.push({ reason: "no_sender_profile", connection_id: connection.id });
        continue;
      }

      // Check if sender has pings enabled
      if (!senderProfile.ping_enabled) {
        skipped.push({ reason: "ping_disabled", connection_id: connection.id });
        continue;
      }

      // Get receiver profile and check subscription
      const receiverProfile = receiverProfileMap.get(connection.receiver_id);
      if (!receiverProfile) {
        skipped.push({ reason: "no_receiver_profile", connection_id: connection.id });
        continue;
      }

      if (!isReceiverSubscriptionActive(receiverProfile)) {
        skipped.push({ reason: "receiver_subscription_inactive", connection_id: connection.id });
        continue;
      }

      // Check if sender is on break
      const senderBreaks = senderBreaksMap.get(connection.sender_id) || [];
      const onBreak = isSenderOnBreak(senderBreaks, today);

      // Get sender's timezone for proper time conversion
      // Phase 6.1: "9 AM local" means 9 AM wherever sender currently is
      const senderTimezone = senderTimezoneMap.get(connection.sender_id) || 'UTC';

      // Calculate scheduled time and deadline
      // ping_time is in sender's local time, convert to UTC using their timezone
      const scheduledTime = calculateScheduledTime(senderProfile.ping_time, today, senderTimezone);
      const deadlineTime = calculateDeadline(scheduledTime);

      // Create ping record
      const pingRecord: PingRecord = {
        connection_id: connection.id,
        sender_id: connection.sender_id,
        receiver_id: connection.receiver_id,
        scheduled_time: scheduledTime.toISOString(),
        deadline_time: deadlineTime.toISOString(),
        status: onBreak ? "on_break" : "pending",
      };

      pingsToCreate.push(pingRecord);
    }

    // 7. Insert all pings in batch
    let insertedCount = 0;
    if (pingsToCreate.length > 0) {
      const { data: insertedPings, error: insertError } = await supabaseClient
        .from("pings")
        .insert(pingsToCreate)
        .select();

      if (insertError) {
        throw new Error(`Failed to insert pings: ${insertError.message}`);
      }

      insertedCount = insertedPings?.length || 0;
      console.log(`[generate-daily-pings] Successfully created ${insertedCount} pings`);
    }

    // 8. Log the results
    const onBreakCount = pingsToCreate.filter((p) => p.status === "on_break").length;
    const pendingCount = pingsToCreate.filter((p) => p.status === "pending").length;

    const result = {
      success: true,
      date: todayStr,
      timestamp: now.toISOString(),
      total_connections: connections.length,
      pings_created: insertedCount,
      pending_pings: pendingCount,
      on_break_pings: onBreakCount,
      skipped: skipped.length,
      skipped_details: skipped.reduce((acc, s) => {
        acc[s.reason] = (acc[s.reason] || 0) + 1;
        return acc;
      }, {} as Record<string, number>),
    };

    console.log("[generate-daily-pings] Completed:", JSON.stringify(result));

    // 9. Log audit event
    await supabaseClient.from("audit_logs").insert({
      action: "generate_daily_pings",
      resource_type: "pings",
      details: result,
    });

    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error) {
    console.error("[generate-daily-pings] Error:", error);

    const errorResult = {
      success: false,
      error: error instanceof Error ? error.message : "Unknown error",
      timestamp: new Date().toISOString(),
    };

    return new Response(JSON.stringify(errorResult), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});
