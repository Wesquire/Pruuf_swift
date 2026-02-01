// Edge Function: complete-ping
// Handles ping completion for all methods: tap, in_person, late
// Phase 6 Section 6.2: Ping Completion Methods

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface CompletePingRequest {
  // Complete all pending pings for a user
  sender_id: string;
  // Optional: complete a specific ping by ID
  ping_id?: string;
  // Completion method: 'tap', 'in_person'
  method: "tap" | "in_person";
  // Location data for in-person verification
  location?: {
    lat: number;
    lon: number;
    accuracy: number;
  };
}

interface PingRecord {
  id: string;
  connection_id: string;
  sender_id: string;
  receiver_id: string;
  scheduled_time: string;
  deadline_time: string;
  status: string;
}

interface UserRecord {
  id: string;
  phone_number: string;
  primary_role: string;
}

interface NotificationInsert {
  user_id: string;
  type: string;
  title: string;
  body: string;
  metadata: Record<string, unknown>;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Validate request method
    if (req.method !== "POST") {
      return new Response(
        JSON.stringify({ error: "Method not allowed" }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 405,
        }
      );
    }

    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    // Parse request body
    const body: CompletePingRequest = await req.json();
    const { sender_id, ping_id, method, location } = body;

    // Validate required fields
    if (!sender_id) {
      return new Response(
        JSON.stringify({ error: "sender_id is required" }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 400,
        }
      );
    }

    if (!method || !["tap", "in_person"].includes(method)) {
      return new Response(
        JSON.stringify({ error: "method must be 'tap' or 'in_person'" }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 400,
        }
      );
    }

    // Validate location for in-person verification
    if (method === "in_person" && !location) {
      return new Response(
        JSON.stringify({ error: "location is required for in_person verification" }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 400,
        }
      );
    }

    const now = new Date();
    const todayStart = new Date(Date.UTC(
      now.getUTCFullYear(),
      now.getUTCMonth(),
      now.getUTCDate()
    ));

    console.log(`[complete-ping] Processing completion for sender: ${sender_id}, method: ${method}`);

    // Build query to get pending pings
    let pingQuery = supabaseClient
      .from("pings")
      .select("id, connection_id, sender_id, receiver_id, scheduled_time, deadline_time, status")
      .eq("sender_id", sender_id)
      .eq("status", "pending")
      .gte("scheduled_time", todayStart.toISOString());

    // If specific ping_id provided, filter by it
    if (ping_id) {
      pingQuery = pingQuery.eq("id", ping_id);
    }

    const { data: pings, error: pingError } = await pingQuery;

    if (pingError) {
      throw new Error(`Failed to fetch pings: ${pingError.message}`);
    }

    // If no pending pings, still send "I'm OK" notification to all active receivers
    // Requirement: Send notifications every time sender hits OK, even if window closed
    if (!pings || pings.length === 0) {
      console.log(`[complete-ping] No pending pings found for sender: ${sender_id}, sending confirmatory notification`);

      // Fetch active receivers from connections table
      const { data: connections, error: connError } = await supabaseClient
        .from("connections")
        .select("receiver_id")
        .eq("sender_id", sender_id)
        .eq("status", "active");

      if (connError) {
        console.error(`[complete-ping] Failed to fetch connections: ${connError.message}`);
      }

      const receiversFromConnections = connections?.map((c: { receiver_id: string }) => c.receiver_id) || [];
      const completedAt = now.toISOString();

      if (receiversFromConnections.length > 0) {
        // Get sender's display info for notifications
        const { data: sender, error: senderError } = await supabaseClient
          .from("users")
          .select("id, phone_number, primary_role")
          .eq("id", sender_id)
          .single();

        if (senderError) {
          console.error(`[complete-ping] Failed to fetch sender info: ${senderError.message}`);
        }

        const senderName = (sender as UserRecord)?.phone_number || "Your connection";

        // Create in-app notifications for all receivers
        const notifications: NotificationInsert[] = receiversFromConnections.map((receiverId: string) => ({
          user_id: receiverId,
          type: "sender_ok_confirmation",
          title: "Check-In Received",
          body: `${senderName} is okay!`,
          metadata: {
            sender_id: sender_id,
            method: method,
            is_late: false,
            completed_at: completedAt,
            ping_count: 0,
            is_confirmatory: true, // Flag to indicate this is a repeat/confirmatory notification
          },
        }));

        const { error: notifyError } = await supabaseClient
          .from("notifications")
          .insert(notifications);

        if (notifyError) {
          console.error(`[complete-ping] Failed to create notifications: ${notifyError.message}`);
        } else {
          console.log(`[complete-ping] Created ${notifications.length} confirmatory notifications`);
        }

        // Send push notifications via APNs
        try {
          const { error: pushError } = await supabaseClient.functions.invoke(
            "send-ping-notification",
            {
              body: {
                type: "sender_ok_confirmation",
                sender_id: sender_id,
                receiver_ids: receiversFromConnections,
                ping_id: null,
                additional_data: {
                  completed_at: completedAt,
                  method: method,
                  is_confirmatory: true,
                },
              },
            }
          );

          if (pushError) {
            console.error(`[complete-ping] Failed to send push notifications: ${pushError.message}`);
          } else {
            console.log(`[complete-ping] Sent confirmatory push notifications to ${receiversFromConnections.length} receivers`);
          }
        } catch (pushErr) {
          console.error(`[complete-ping] Push notification error:`, pushErr);
        }

        // Log audit event for confirmatory ping
        await supabaseClient.from("audit_logs").insert({
          user_id: sender_id,
          action: "confirmatory_ping",
          resource_type: "ping",
          details: {
            method,
            completed_count: 0,
            receivers_notified: receiversFromConnections.length,
            is_confirmatory: true,
            timestamp: completedAt,
          },
        });
      }

      return new Response(
        JSON.stringify({
          success: true,
          message: "No pending pings to complete, but receivers notified",
          completed_count: 0,
          late_count: 0,
          on_time_count: 0,
          receivers_notified: receiversFromConnections.length,
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 200,
        }
      );
    }

    console.log(`[complete-ping] Found ${pings.length} pending pings`);

    // Determine which pings are on-time vs late
    const onTimePings: PingRecord[] = [];
    const latePings: PingRecord[] = [];

    for (const ping of pings as PingRecord[]) {
      const deadline = new Date(ping.deadline_time);
      if (now > deadline) {
        latePings.push(ping);
      } else {
        onTimePings.push(ping);
      }
    }

    // Build verification location object if provided
    const verificationLocation = location
      ? {
          lat: location.lat,
          lon: location.lon,
          accuracy: location.accuracy,
        }
      : null;

    // Complete all pings
    const allPingIds = pings.map((p: PingRecord) => p.id);
    const completedAt = now.toISOString();

    const updateData: Record<string, unknown> = {
      completed_at: completedAt,
      completion_method: method,
      status: "completed",
    };

    // Add verification location if in-person
    if (method === "in_person" && verificationLocation) {
      updateData.verification_location = verificationLocation;
    }

    const { error: updateError } = await supabaseClient
      .from("pings")
      .update(updateData)
      .in("id", allPingIds);

    if (updateError) {
      throw new Error(`Failed to complete pings: ${updateError.message}`);
    }

    console.log(`[complete-ping] Completed ${allPingIds.length} pings`);

    // Get sender's display info for notifications
    const { data: sender, error: senderError } = await supabaseClient
      .from("users")
      .select("id, phone_number, primary_role")
      .eq("id", sender_id)
      .single();

    if (senderError) {
      console.error(`[complete-ping] Failed to fetch sender info: ${senderError.message}`);
    }

    const senderName = (sender as UserRecord)?.phone_number || "Your connection";

    // Send notifications to all receivers
    const receiversToNotify = new Set<string>();
    for (const ping of pings as PingRecord[]) {
      receiversToNotify.add(ping.receiver_id);
    }

    const notifications: NotificationInsert[] = [];
    const isLate = latePings.length > 0 && onTimePings.length === 0;

    for (const receiverId of receiversToNotify) {
      let title: string;
      let body: string;
      let notificationType: string;

      if (isLate) {
        title = "Late Check-In";
        body = `${senderName} pinged late at ${new Date().toLocaleTimeString()}`;
        notificationType = "ping_late";
      } else if (method === "in_person") {
        title = "In-Person Verification";
        body = `${senderName} verified in person - all is well!`;
        notificationType = "ping_completed";
      } else {
        title = "Ping Received";
        body = `${senderName} is okay!`;
        notificationType = "ping_completed";
      }

      notifications.push({
        user_id: receiverId,
        type: notificationType,
        title,
        body,
        metadata: {
          sender_id: sender_id,
          method: method,
          is_late: isLate,
          completed_at: completedAt,
          ping_count: allPingIds.length,
        },
      });
    }

    // Insert notifications and send push notifications
    if (notifications.length > 0) {
      const { error: notifyError } = await supabaseClient
        .from("notifications")
        .insert(notifications);

      if (notifyError) {
        console.error(`[complete-ping] Failed to create notifications: ${notifyError.message}`);
        // Don't fail the request for notification errors
      } else {
        console.log(`[complete-ping] Created ${notifications.length} in-app notifications`);
      }

      // Send push notifications via APNs
      try {
        const notificationType = isLate ? "ping_completed_late" : "ping_completed";
        const { error: pushError } = await supabaseClient.functions.invoke(
          "send-ping-notification",
          {
            body: {
              type: notificationType,
              sender_id: sender_id,
              receiver_ids: Array.from(receiversToNotify),
              ping_id: allPingIds[0], // Use first ping ID for reference
              additional_data: {
                completed_at: completedAt,
                method: method,
              },
            },
          }
        );

        if (pushError) {
          console.error(`[complete-ping] Failed to send push notifications: ${pushError.message}`);
        } else {
          console.log(`[complete-ping] Sent push notifications to ${receiversToNotify.size} receivers`);
        }
      } catch (pushErr) {
        console.error(`[complete-ping] Push notification error:`, pushErr);
        // Don't fail the request for push notification errors
      }
    }

    // Log audit event
    await supabaseClient.from("audit_logs").insert({
      user_id: sender_id,
      action: "complete_ping",
      resource_type: "ping",
      details: {
        method,
        completed_count: allPingIds.length,
        on_time_count: onTimePings.length,
        late_count: latePings.length,
        has_location: !!verificationLocation,
        timestamp: completedAt,
      },
    });

    // Build response
    const result = {
      success: true,
      completed_count: allPingIds.length,
      on_time_count: onTimePings.length,
      late_count: latePings.length,
      method: method,
      completed_at: completedAt,
      receivers_notified: receiversToNotify.size,
      has_location_verification: !!verificationLocation,
      ping_ids: allPingIds,
    };

    console.log(`[complete-ping] Success:`, JSON.stringify(result));

    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error) {
    console.error("[complete-ping] Error:", error);

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
