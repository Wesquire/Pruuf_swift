// Edge Function: send-ping-notification
// Sends push notifications to connected users when a ping is received or missed
// Uses the send-apns-notification function for actual APNs delivery

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface PingNotificationRequest {
  type: "ping_completed" | "ping_completed_late" | "ping_missed" | "ping_reminder" | "connection_new" | "trial_ending" | "break_started" | "break_ended";
  sender_id: string;
  receiver_ids?: string[];
  ping_id?: string;
  connection_id?: string;
  additional_data?: Record<string, unknown>;
}

interface NotificationContent {
  title: string;
  body: string;
  category: string;
  thread_id?: string;
  deeplink: string;
  badge?: number;
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

    const { type, sender_id, receiver_ids, ping_id, connection_id, additional_data }: PingNotificationRequest = await req.json();

    // Get sender's display name
    const { data: sender, error: senderError } = await supabaseClient
      .from("users")
      .select("phone_number")
      .eq("id", sender_id)
      .single();

    if (senderError) {
      throw senderError;
    }

    // Get sender's profile for display name
    const { data: senderProfile } = await supabaseClient
      .from("sender_profiles")
      .select("display_name")
      .eq("user_id", sender_id)
      .single();

    const senderName = senderProfile?.display_name || sender?.phone_number || "Someone";

    // Determine which users to notify
    let targetUserIds: string[] = [];

    if (receiver_ids && receiver_ids.length > 0) {
      targetUserIds = receiver_ids;
    } else {
      // Get all connected receivers for this sender
      const { data: connections, error: connError } = await supabaseClient
        .from("connections")
        .select("receiver_id")
        .eq("sender_id", sender_id)
        .eq("status", "active");

      if (connError) {
        throw connError;
      }

      targetUserIds = connections?.map((c) => c.receiver_id) || [];
    }

    if (targetUserIds.length === 0) {
      return new Response(
        JSON.stringify({ success: true, message: "No receivers to notify", sent: 0 }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 200,
        }
      );
    }

    // Map notification request types to database notification types
    const getNotificationType = (requestType: string): string => {
      switch (requestType) {
        case "ping_completed":
          return "ping_completed_ontime";
        case "ping_completed_late":
          return "ping_completed_late";
        case "ping_missed":
          return "missed_ping";
        case "ping_reminder":
          return "ping_reminder";
        case "connection_new":
          return "connection_request";
        case "trial_ending":
          return "trial_ending";
        case "break_started":
        case "break_ended":
          return "break_started";
        default:
          return requestType;
      }
    };

    const notificationType = getNotificationType(type);

    // Filter out receivers based on their notification preferences
    // This checks: master toggle, per-sender muting, and type-specific preferences
    const { data: receiverPrefs } = await supabaseClient
      .from("users")
      .select("id, notification_preferences")
      .in("id", targetUserIds);

    const prefsByUserId = new Map<string, {
      notifications_enabled?: boolean;
      muted_sender_ids?: string[];
      ping_completed_notifications?: boolean;
      missed_ping_alerts?: boolean;
      connection_requests?: boolean;
      sound_enabled?: boolean;
      vibration_enabled?: boolean;
    } | null>();

    const eligibleReceivers = (receiverPrefs || [])
      .filter((u) => {
        const prefs = u.notification_preferences as {
          notifications_enabled?: boolean;
          muted_sender_ids?: string[];
          ping_completed_notifications?: boolean;
          missed_ping_alerts?: boolean;
          connection_requests?: boolean;
          sound_enabled?: boolean;
          vibration_enabled?: boolean;
        } | null;

        prefsByUserId.set(u.id, prefs);

        // Check master toggle (default: enabled)
        if (prefs?.notifications_enabled === false) {
          return false;
        }

        // Check per-sender muting
        const mutedIds = prefs?.muted_sender_ids || [];
        if (mutedIds.includes(sender_id)) {
          return false;
        }

        // Check type-specific preferences
        switch (notificationType) {
          case "ping_completed_ontime":
          case "ping_completed_late":
          case "break_started":
            // Check ping_completed_notifications (default: true)
            return prefs?.ping_completed_notifications !== false;
          case "missed_ping":
            // Check missed_ping_alerts (default: true)
            return prefs?.missed_ping_alerts !== false;
          case "connection_request":
            // Check connection_requests (default: true)
            return prefs?.connection_requests !== false;
          case "trial_ending":
          case "payment_reminder":
            // Always send payment-related notifications
            return true;
          default:
            return true;
        }
      })
      .map((u) => u.id);

    if (eligibleReceivers.length === 0) {
      return new Response(
        JSON.stringify({ success: true, message: "All receivers have disabled this notification type", sent: 0 }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 200,
        }
      );
    }

    // Use eligibleReceivers instead of notMutedReceivers for the rest of the function
    const notMutedReceivers = eligibleReceivers;

    // Per plan.md Section 9.2: Receivers with expired subscriptions stop getting ping notifications
    // Filter out receivers with expired/inactive subscriptions (except for trial_ending notifications which should always be sent)
    let activeReceivers = notMutedReceivers;
    if (type !== "trial_ending") {
      const { data: receiverProfiles } = await supabaseClient
        .from("receiver_profiles")
        .select("user_id, subscription_status, trial_end_date, subscription_end_date")
        .in("user_id", notMutedReceivers);

      const now = new Date();
      activeReceivers = notMutedReceivers.filter((userId) => {
        const profile = receiverProfiles?.find((p) => p.user_id === userId);
        if (!profile) {
          // If no profile, user might be sender-only, allow notification
          return true;
        }

        const status = profile.subscription_status;

        // Active subscription
        if (status === "active") {
          if (profile.subscription_end_date) {
            return new Date(profile.subscription_end_date) > now;
          }
          return true;
        }

        // Trial subscription
        if (status === "trial") {
          if (profile.trial_end_date) {
            return new Date(profile.trial_end_date) > now;
          }
          return true;
        }

        // Expired, canceled, or past_due - don't send ping notifications
        return false;
      });

      if (activeReceivers.length === 0) {
        return new Response(
          JSON.stringify({ success: true, message: "All receivers have inactive subscriptions", sent: 0 }),
          {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
            status: 200,
          }
        );
      }
    }

    // Build notification content based on type
    const content = buildNotificationContent(type, senderName, sender_id, additional_data);

    // Build notification data payload
    const notificationData: Record<string, unknown> = {
      type,
      sender_id,
    };

    if (ping_id) {
      notificationData.ping_id = ping_id;
    }

    if (connection_id) {
      notificationData.connection_id = connection_id;
    }

    const soundEnabledReceivers: string[] = [];
    const silentReceivers: string[] = [];

    for (const userId of activeReceivers) {
      const prefs = prefsByUserId.get(userId);
      const soundEnabled = prefs?.sound_enabled !== false;
      if (soundEnabled) {
        soundEnabledReceivers.push(userId);
      } else {
        silentReceivers.push(userId);
      }
    }

    const apnsPayloadBase = {
      title: content.title,
      body: content.body,
      type,
      category: content.category,
      thread_id: content.thread_id || `sender_${sender_id}`,
      data: {
        ...notificationData,
        deeplink: content.deeplink,
      },
      badge: content.badge,
      priority: isPriorityNotification(type) ? "high" : "normal",
    };

    const apnsResults: unknown[] = [];

    const sendApns = async (userIds: string[], sound: string | null) => {
      if (userIds.length === 0) {
        return;
      }

      const { data: apnsResult, error: apnsError } = await supabaseClient.functions.invoke(
        "send-apns-notification",
        { body: { ...apnsPayloadBase, user_ids: userIds, sound } }
      );

      if (apnsError) {
        console.error("APNs function error:", apnsError);
        return;
      }

      apnsResults.push(apnsResult);
    };

    await sendApns(soundEnabledReceivers, "default");
    await sendApns(silentReceivers, null);

    return new Response(
      JSON.stringify({
        success: true,
        type,
        recipients: activeReceivers.length,
        apns_result: apnsResults,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      }
    );
  } catch (error: unknown) {
    console.error("Error sending ping notification:", error);
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

function buildNotificationContent(
  type: string,
  senderName: string,
  senderId: string,
  additionalData?: Record<string, unknown>
): NotificationContent {
  switch (type) {
    case "ping_completed":
      // Ping Completed (to Receiver) - per Section 8.2 plan.md
      const completedTime = additionalData?.completed_at
        ? new Date(additionalData.completed_at as string).toLocaleTimeString([], {
            hour: "numeric",
            minute: "2-digit",
          })
        : new Date().toLocaleTimeString([], {
            hour: "numeric",
            minute: "2-digit",
          });
      return {
        title: `${senderName} is okay!`,
        body: `Checked in at ${completedTime} ✓`,
        category: "PING_RECEIVED",
        deeplink: "pruuf://dashboard",
      };

    case "ping_completed_late":
      // Late Ping Completed (to Receiver)
      const lateTime = additionalData?.completed_at
        ? new Date(additionalData.completed_at as string).toLocaleTimeString([], {
            hour: "numeric",
            minute: "2-digit",
          })
        : "recently";
      return {
        title: "Late Check-in Received",
        body: `${senderName} pinged late at ${lateTime}`,
        category: "PING_RECEIVED",
        deeplink: "pruuf://dashboard",
      };

    case "ping_missed":
      // Missed Ping Alert (to Receiver) - per Section 8.2 plan.md
      const lastSeen = additionalData?.last_seen
        ? new Date(additionalData.last_seen as string).toLocaleTimeString([], {
            hour: "numeric",
            minute: "2-digit",
          })
        : "unknown";
      return {
        title: "Missed Ping Alert",
        body: `${senderName} missed their ping. Last seen ${lastSeen}.`,
        category: "MISSED_PING",
        deeplink: `pruuf://sender/${senderId}`,
        badge: 1,
      };

    case "ping_reminder":
      // Ping Reminder (to Sender) - per Section 8.2 plan.md
      return {
        title: "Time to ping!",
        body: "Tap to let everyone know you're okay.",
        category: "PING_REMINDER",
        deeplink: "pruuf://dashboard",
        badge: 1,
      };

    case "connection_new":
      // Connection Request (to Receiver) - per Section 8.2 plan.md
      return {
        title: "New Connection",
        body: `${senderName} is now sending you pings`,
        category: "CONNECTION_REQUEST",
        deeplink: "pruuf://connections",
      };

    case "trial_ending":
      // Trial Ending (to Receiver) - per plan.md Section 9.2
      const daysRemaining = additionalData?.days_remaining ?? 3;
      let trialTitle = "Trial Ending Soon";
      let trialBody = "";

      if (daysRemaining === 0) {
        // Day 15: Trial has ended
        trialTitle = "Trial Ended";
        trialBody = "Your trial has ended. Subscribe to continue.";
      } else if (daysRemaining === 1) {
        // Day 14: Trial ends tomorrow
        trialBody = "Your trial ends tomorrow";
      } else if (daysRemaining === 3) {
        // Day 12: Trial ends in 3 days
        trialBody = "Your free trial ends in 3 days. Subscribe to keep your peace of mind.";
      } else {
        trialBody = `Your free trial ends in ${daysRemaining} days. Subscribe to keep your peace of mind.`;
      }

      return {
        title: trialTitle,
        body: trialBody,
        category: "TRIAL_ENDING",
        deeplink: "pruuf://subscription",
      };

    case "break_started":
      const endDate = additionalData?.end_date
        ? new Date(additionalData.end_date as string).toLocaleDateString()
        : "soon";
      return {
        title: "Break Started",
        body: `${senderName} is on break until ${endDate}`,
        category: "BREAK_NOTIFICATION",
        deeplink: "pruuf://dashboard",
      };

    case "break_ended":
      return {
        title: "Break Ended",
        body: `${senderName} ended their break early`,
        category: "BREAK_NOTIFICATION",
        deeplink: "pruuf://dashboard",
      };

    default:
      return {
        title: "PRUUF Notification",
        body: `${senderName} has an update`,
        category: "DEFAULT",
        deeplink: "pruuf://dashboard",
      };
  }
}

function isPriorityNotification(type: string): boolean {
  return ["ping_missed", "ping_reminder"].includes(type);
}
