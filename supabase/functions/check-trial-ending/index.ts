// Edge Function: check-trial-ending
// Scheduled function to check for users with trials ending soon and send notifications
// Phase 9 Section 9.2: Trial Period notifications
// This function is called via pg_cron or Supabase scheduled functions

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface ReceiverProfile {
  user_id: string;
  subscription_status: string;
  trial_end_date: string;
}

interface UserInfo {
  id: string;
  notification_preferences: {
    mutedNotificationTypes?: string[];
  } | null;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    const now = new Date();
    const today = now.toISOString().split("T")[0];

    // Check for trials ending in 3 days (Day 12), 1 day (Day 14), and today (Day 15)
    // Per plan.md Section 9.2:
    // - Day 12: "Your trial ends in 3 days"
    // - Day 14: "Your trial ends tomorrow"
    // - Day 15: "Your trial has ended. Subscribe to continue"
    const notificationDays = [3, 1, 0];
    const results = {
      checked: 0,
      notified: 0,
      expired: 0,
      errors: 0,
    };

    for (const daysRemaining of notificationDays) {
      // Calculate the target date (trial_end_date)
      const targetDate = new Date(now);
      targetDate.setDate(targetDate.getDate() + daysRemaining);
      const targetDateStr = targetDate.toISOString().split("T")[0];

      // Find receiver profiles whose trial ends on the target date
      // They should be on 'trial' status
      const { data: trialProfiles, error: queryError } = await supabaseClient
        .from("receiver_profiles")
        .select("user_id, subscription_status, trial_end_date")
        .eq("subscription_status", "trial")
        .gte("trial_end_date", `${targetDateStr}T00:00:00Z`)
        .lt("trial_end_date", `${targetDateStr}T23:59:59Z`);

      if (queryError) {
        console.error(`Error querying trial profiles for ${daysRemaining} days:`, queryError);
        results.errors++;
        continue;
      }

      results.checked += trialProfiles?.length || 0;

      for (const profile of trialProfiles || []) {
        // Get user info for notification preferences
        const { data: userInfo, error: userError } = await supabaseClient
          .from("users")
          .select("id, notification_preferences")
          .eq("id", profile.user_id)
          .single();

        if (userError || !userInfo) {
          console.error(`Error fetching user info for ${profile.user_id}:`, userError);
          results.errors++;
          continue;
        }

        // Check if user has muted trial ending notifications
        const prefs = userInfo.notification_preferences as { mutedNotificationTypes?: string[] } | null;
        const mutedTypes = prefs?.mutedNotificationTypes || [];
        if (mutedTypes.includes("trial_ending")) {
          console.log(`User ${profile.user_id} has muted trial_ending notifications, skipping`);
          continue;
        }

        // Check if we already sent this specific notification today
        const { data: existingNotification } = await supabaseClient
          .from("notifications")
          .select("id")
          .eq("user_id", profile.user_id)
          .eq("type", "trial_ending")
          .gte("sent_at", `${today}T00:00:00Z`)
          .single();

        if (existingNotification) {
          console.log(`Already sent trial ending notification to ${profile.user_id} today, skipping`);
          continue;
        }

        // Send trial ending notification
        try {
          // Build notification content per plan.md Section 9.2
          let title = "";
          let body = "";

          if (daysRemaining === 0) {
            // Day 15: Trial has ended
            title = "Trial Ended";
            body = "Your trial has ended. Subscribe to continue.";

            // Also expire the subscription status
            const { error: expireError } = await supabaseClient
              .from("receiver_profiles")
              .update({
                subscription_status: "expired",
                updated_at: now.toISOString()
              })
              .eq("user_id", profile.user_id);

            if (expireError) {
              console.error(`Error expiring subscription for ${profile.user_id}:`, expireError);
            } else {
              results.expired++;
              console.log(`Expired trial for user ${profile.user_id}`);
            }
          } else if (daysRemaining === 1) {
            // Day 14: Trial ends tomorrow
            title = "Trial Ending Soon";
            body = "Your trial ends tomorrow";
          } else if (daysRemaining === 3) {
            // Day 12: Trial ends in 3 days
            title = "Trial Ending Soon";
            body = "Your trial ends in 3 days";
          } else {
            title = "Trial Ending Soon";
            body = `Your free trial ends in ${daysRemaining} days. Subscribe to keep your peace of mind.`;
          }

          // Insert notification record
          const { error: insertError } = await supabaseClient
            .from("notifications")
            .insert({
              user_id: profile.user_id,
              type: "trial_ending",
              title,
              body,
              metadata: {
                days_remaining: daysRemaining,
                trial_end_date: profile.trial_end_date,
              },
              delivery_status: "pending",
              sent_at: now.toISOString(),
            });

          if (insertError) {
            console.error(`Error inserting notification for ${profile.user_id}:`, insertError);
            results.errors++;
            continue;
          }

          // Send push notification via send-ping-notification function
          const notifyResponse = await fetch(
            `${Deno.env.get("SUPABASE_URL")}/functions/v1/send-ping-notification`,
            {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
              },
              body: JSON.stringify({
                type: "trial_ending",
                sender_id: profile.user_id, // Use user's own ID since it's a system notification
                receiver_ids: [profile.user_id],
                additional_data: {
                  days_remaining: daysRemaining,
                },
              }),
            }
          );

          if (!notifyResponse.ok) {
            console.error(`Failed to send push notification to ${profile.user_id}:`, await notifyResponse.text());
            results.errors++;
          } else {
            results.notified++;
            console.log(`Sent trial ending notification to ${profile.user_id} (${daysRemaining} days remaining)`);
          }
        } catch (err) {
          console.error(`Error processing user ${profile.user_id}:`, err);
          results.errors++;
        }
      }
    }

    console.log("Trial ending check completed:", results);

    return new Response(
      JSON.stringify({
        success: true,
        ...results,
        timestamp: now.toISOString(),
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      }
    );
  } catch (error: unknown) {
    console.error("Error checking trial ending:", error);
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
