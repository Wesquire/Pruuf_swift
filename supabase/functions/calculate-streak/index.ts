// Edge Function: calculate-streak
// Calculate ping streak for a sender-receiver connection
// Phase 6 Section 6.4: Ping Streak Calculation
//
// Rules:
//   1. Consecutive days of completed pings
//   2. Breaks do NOT break the streak (counted as completed)
//   3. Missed pings reset streak to 0
//   4. Late pings count toward streak (they have status 'completed')

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface CalculateStreakRequest {
  // The sender's user ID
  sender_id: string;
  // Optional: specific receiver to calculate streak for
  receiver_id?: string;
  // Optional: connection ID (will be resolved to sender/receiver)
  connection_id?: string;
}

interface PingRecord {
  scheduled_time: string;
  status: string;
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
    const body: CalculateStreakRequest = await req.json();
    let { sender_id, receiver_id, connection_id } = body;

    // If connection_id provided, resolve to sender/receiver
    if (connection_id && (!sender_id || !receiver_id)) {
      const { data: connection, error: connError } = await supabaseClient
        .from("connections")
        .select("sender_id, receiver_id")
        .eq("id", connection_id)
        .single();

      if (connError || !connection) {
        return new Response(
          JSON.stringify({ error: "Connection not found" }),
          {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
            status: 404,
          }
        );
      }

      sender_id = connection.sender_id;
      receiver_id = connection.receiver_id;
    }

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

    console.log(`[calculate-streak] Calculating streak for sender: ${sender_id}, receiver: ${receiver_id || "all"}`);

    // Get all pings for this sender (and optionally receiver), ordered by date descending
    let pingQuery = supabaseClient
      .from("pings")
      .select("scheduled_time, status")
      .eq("sender_id", sender_id)
      .order("scheduled_time", { ascending: false })
      .limit(730); // Max 2 years

    if (receiver_id) {
      pingQuery = pingQuery.eq("receiver_id", receiver_id);
    }

    const { data: pings, error: pingError } = await pingQuery;

    if (pingError) {
      throw new Error(`Failed to fetch pings: ${pingError.message}`);
    }

    if (!pings || pings.length === 0) {
      console.log(`[calculate-streak] No pings found for sender: ${sender_id}`);
      return new Response(
        JSON.stringify({ streak: 0 }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 200,
        }
      );
    }

    // Group pings by date and determine the best status for each day
    const pingsByDate = new Map<string, string>();

    for (const ping of pings as PingRecord[]) {
      const date = new Date(ping.scheduled_time).toISOString().split("T")[0];
      const existingStatus = pingsByDate.get(date);

      // Priority: completed > on_break > pending > missed
      // If any ping on this date is completed, the day is completed
      if (!existingStatus) {
        pingsByDate.set(date, ping.status);
      } else if (ping.status === "completed") {
        pingsByDate.set(date, "completed");
      } else if (ping.status === "on_break" && existingStatus !== "completed") {
        pingsByDate.set(date, "on_break");
      }
      // pending and missed don't override better statuses
    }

    // Convert to sorted array of dates
    const dates = Array.from(pingsByDate.keys()).sort().reverse();

    if (dates.length === 0) {
      return new Response(
        JSON.stringify({ streak: 0 }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 200,
        }
      );
    }

    // Calculate streak
    let streak = 0;
    const today = new Date().toISOString().split("T")[0];
    let currentDate = today;
    let hasStartedCounting = false;

    // Get the date we expect to check (today or yesterday depending on today's status)
    const todayStatus = pingsByDate.get(today);

    // If today's ping is missed, streak is 0
    if (todayStatus === "missed") {
      return new Response(
        JSON.stringify({ streak: 0 }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 200,
        }
      );
    }

    // If today's ping is completed or on_break, count it and start from there
    if (todayStatus === "completed" || todayStatus === "on_break") {
      streak = 1;
      hasStartedCounting = true;
    }

    // Go backwards through dates starting from yesterday
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    currentDate = yesterday.toISOString().split("T")[0];

    while (true) {
      const status = pingsByDate.get(currentDate);

      if (!status) {
        // No ping for this date
        if (hasStartedCounting) {
          // We were counting and hit a gap - streak ends
          break;
        }
        // Haven't started counting yet, keep going back
      } else if (status === "missed") {
        // Missed ping breaks the streak
        break;
      } else if (status === "completed" || status === "on_break") {
        // These count toward streak
        streak++;
        hasStartedCounting = true;
      } else if (status === "pending") {
        // Pending shouldn't exist for past days, but treat as break if it does
        if (hasStartedCounting) {
          break;
        }
      }

      // Move to previous day
      const prevDate = new Date(currentDate);
      prevDate.setDate(prevDate.getDate() - 1);
      currentDate = prevDate.toISOString().split("T")[0];

      // Safety: don't go back more than 2 years
      const twoYearsAgo = new Date();
      twoYearsAgo.setFullYear(twoYearsAgo.getFullYear() - 2);
      if (new Date(currentDate) < twoYearsAgo) {
        break;
      }

      // Also stop if we've gone past the earliest ping date
      const earliestDate = dates[dates.length - 1];
      if (currentDate < earliestDate && hasStartedCounting) {
        break;
      }
    }

    console.log(`[calculate-streak] Calculated streak: ${streak} for sender: ${sender_id}`);

    return new Response(
      JSON.stringify({ streak }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      }
    );
  } catch (error) {
    console.error("[calculate-streak] Error:", error);

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
