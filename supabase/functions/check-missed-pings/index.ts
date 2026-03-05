// Edge Function: check-missed-pings
// Scheduled function to check for missed pings and trigger notifications
// This function is called via pg_cron or Supabase scheduled functions
//
// No grace period: deadline = scheduled time
// Receivers are notified IMMEDIATELY when Pruuf time passes without check-in
// A SECOND notification comes 60 minutes later if sender STILL hasn't sent

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Second notification delay in minutes
const FOLLOWUP_NOTIFICATION_MINUTES = 60;

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

    // Get current time
    const now = new Date();
    const today = now.toISOString().split("T")[0];

    // Find users who should have pinged but haven't
    // Query users with active ping schedules
    const { data: usersToCheck, error: queryError } = await supabaseClient
      .from("users")
      .select(`
        id,
        display_name,
        phone,
        timezone,
        ping_schedules!inner (
          ping_window_start,
          ping_window_end,
          is_active
        )
      `)
      .eq("ping_schedules.is_active", true);

    if (queryError) {
      throw queryError;
    }

    const missedPingUsers: string[] = [];
    const followupUsers: string[] = [];
    const remindUsers: string[] = [];

    for (const user of usersToCheck || []) {
      const schedule = user.ping_schedules[0];
      const userTimezone = user.timezone || "UTC";

      // Calculate user's current time in their timezone
      const userNow = new Date(now.toLocaleString("en-US", { timeZone: userTimezone }));
      const currentTime = userNow.toTimeString().slice(0, 5); // HH:MM format

      // Deadline = scheduled ping window end (no grace period)
      const windowEnd = schedule.ping_window_end;

      // Check if user has pinged today
      const { data: todaysPing, error: pingError } = await supabaseClient
        .from("pings")
        .select("id, created_at")
        .eq("user_id", user.id)
        .gte("created_at", `${today}T00:00:00Z`)
        .lt("created_at", `${today}T23:59:59Z`)
        .single();

      if (pingError && pingError.code !== "PGRST116") { // PGRST116 = no rows found
        console.error(`Error checking ping for user ${user.id}:`, pingError);
        continue;
      }

      const hasPingedToday = !!todaysPing;

      if (!hasPingedToday) {
        // No grace period: check if we're past the scheduled time
        const [endHour, endMin] = windowEnd.split(":").map(Number);
        const scheduledEnd = new Date(userNow);
        scheduledEnd.setHours(endHour, endMin, 0, 0);

        // Calculate followup time (scheduled time + 60 minutes)
        const followupTime = new Date(scheduledEnd);
        followupTime.setMinutes(followupTime.getMinutes() + FOLLOWUP_NOTIFICATION_MINUTES);

        if (userNow > followupTime) {
          // Past scheduled time + 60 minutes: trigger second (followup) notification
          followupUsers.push(user.id);
        } else if (userNow > scheduledEnd) {
          // Past scheduled time but within 60 minutes: first missed notification
          missedPingUsers.push(user.id);
        } else if (currentTime >= schedule.ping_window_start && currentTime <= windowEnd) {
          // User is in their ping window but hasn't pinged - send reminder
          remindUsers.push(user.id);
        }
      }
    }

    // Process missed pings (immediate notification at scheduled time)
    for (const userId of missedPingUsers) {
      // Check if we've already sent the first missed notification today
      const { data: existingMissedNotification } = await supabaseClient
        .from("notifications")
        .select("id")
        .eq("user_id", userId)
        .eq("type", "ping_missed")
        .gte("created_at", `${today}T00:00:00Z`)
        .limit(1)
        .single();

      if (existingMissedNotification) {
        // Already notified, skip
        continue;
      }

      // Record missed ping
      const { error: insertError } = await supabaseClient
        .from("pings")
        .insert({
          user_id: userId,
          status: "missed",
          ping_date: today,
          created_at: now.toISOString(),
        });

      if (insertError) {
        console.error(`Error recording missed ping for ${userId}:`, insertError);
        continue;
      }

      // Trigger IMMEDIATE notification to connected receivers
      // "[Sender] hasn't sent their Pruuf yet."
      const notifyResponse = await fetch(
        `${Deno.env.get("SUPABASE_URL")}/functions/v1/send-ping-notification`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
          },
          body: JSON.stringify({
            type: "ping_missed",
            sender_id: userId,
            additional_data: {
              notification_variant: "immediate",
            },
          }),
        }
      );

      if (!notifyResponse.ok) {
        console.error(`Failed to send missed ping notification for ${userId}`);
      }
    }

    // Process followup notifications (60 minutes after scheduled time, sender still hasn't sent)
    for (const userId of followupUsers) {
      // Check if we've already sent the followup notification today
      const { data: existingFollowup } = await supabaseClient
        .from("notifications")
        .select("id")
        .eq("user_id", userId)
        .eq("type", "ping_missed_followup")
        .gte("created_at", `${today}T00:00:00Z`)
        .limit(1)
        .single();

      if (existingFollowup) {
        // Already sent followup, skip
        continue;
      }

      // Trigger SECOND notification to connected receivers
      // "[Sender] still hasn't sent their Pruuf. It's been 60 minutes past their check-in time."
      const notifyResponse = await fetch(
        `${Deno.env.get("SUPABASE_URL")}/functions/v1/send-ping-notification`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
          },
          body: JSON.stringify({
            type: "ping_missed_followup",
            sender_id: userId,
            additional_data: {
              notification_variant: "followup_60min",
            },
          }),
        }
      );

      if (!notifyResponse.ok) {
        console.error(`Failed to send followup missed ping notification for ${userId}`);
      }
    }

    // Process reminders (only for users who haven't been reminded in the last hour)
    for (const userId of remindUsers) {
      // Check last reminder time
      const { data: lastReminder } = await supabaseClient
        .from("notifications")
        .select("created_at")
        .eq("user_id", userId)
        .eq("type", "ping_reminder")
        .gte("created_at", new Date(now.getTime() - 60 * 60 * 1000).toISOString())
        .single();

      if (!lastReminder) {
        // Send reminder notification directly to user
        await supabaseClient.from("notifications").insert({
          user_id: userId,
          title: "Ping Reminder",
          body: "Don't forget to check in today!",
          type: "ping_reminder",
          read: false,
          created_at: now.toISOString(),
        });
      }
    }

    const result = {
      checked: usersToCheck?.length || 0,
      missed: missedPingUsers.length,
      followups: followupUsers.length,
      reminded: remindUsers.length,
      timestamp: now.toISOString(),
    };

    console.log("Ping check completed:", result);

    return new Response(
      JSON.stringify(result),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      }
    );
  } catch (error: unknown) {
    console.error("Error checking missed pings:", error);
    const errorMessage = error instanceof Error ? error.message : "Internal server error";
    return new Response(
      JSON.stringify({ error: errorMessage }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 500,
      }
    );
  }
});
