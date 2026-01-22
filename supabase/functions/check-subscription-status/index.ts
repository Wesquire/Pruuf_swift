// Edge Function: check-subscription-status
// Validates receiver subscription before operations
// Phase 12 Section 12.2: Edge Function Specifications
//
// POST method
// Accept: { userId: string }
// Return: { status: 'trial'|'active'|'past_due'|'expired', valid: boolean }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface CheckSubscriptionRequest {
  userId: string;
}

interface SubscriptionResponse {
  status: "trial" | "active" | "past_due" | "canceled" | "expired" | null;
  valid: boolean;
  trial_days_remaining?: number;
  subscription_end_date?: string;
  message?: string;
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
        JSON.stringify({
          error: "Method not allowed",
          code: "METHOD_NOT_ALLOWED"
        }),
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
    const body: CheckSubscriptionRequest = await req.json();
    const { userId } = body;

    // Validate required fields
    if (!userId) {
      return new Response(
        JSON.stringify({
          error: "userId is required",
          code: "INVALID_REQUEST"
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 400,
        }
      );
    }

    console.log(`[check-subscription-status] Checking subscription for user: ${userId}`);

    // Get receiver profile
    const { data: profile, error: profileError } = await supabaseClient
      .from("receiver_profiles")
      .select("subscription_status, trial_start_date, trial_end_date, subscription_start_date, subscription_end_date")
      .eq("user_id", userId)
      .single();

    if (profileError) {
      // User might not have a receiver profile (sender-only)
      if (profileError.code === "PGRST116") {
        console.log(`[check-subscription-status] No receiver profile found for user: ${userId}`);
        return new Response(
          JSON.stringify({
            status: null,
            valid: true, // Senders don't need subscription
            message: "No receiver profile - user may be sender-only",
          } as SubscriptionResponse),
          {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
            status: 200,
          }
        );
      }
      throw new Error(`Failed to fetch receiver profile: ${profileError.message}`);
    }

    const now = new Date();
    let currentStatus = profile.subscription_status;
    let needsUpdate = false;

    // Check if trial has expired
    if (currentStatus === "trial" && profile.trial_end_date) {
      const trialEnd = new Date(profile.trial_end_date);
      if (now > trialEnd) {
        currentStatus = "expired";
        needsUpdate = true;
        console.log(`[check-subscription-status] Trial expired for user: ${userId}`);
      }
    }

    // Check if active subscription has expired
    if (currentStatus === "active" && profile.subscription_end_date) {
      const subEnd = new Date(profile.subscription_end_date);
      if (now > subEnd) {
        currentStatus = "expired";
        needsUpdate = true;
        console.log(`[check-subscription-status] Subscription expired for user: ${userId}`);
      }
    }

    // Check past_due with 3-day grace period
    if (currentStatus === "past_due" && profile.subscription_end_date) {
      const subEnd = new Date(profile.subscription_end_date);
      const gracePeriodEnd = new Date(subEnd.getTime() + 3 * 24 * 60 * 60 * 1000); // 3 days
      if (now > gracePeriodEnd) {
        currentStatus = "expired";
        needsUpdate = true;
        console.log(`[check-subscription-status] Past-due grace period ended for user: ${userId}`);
      }
    }

    // Update status if needed
    if (needsUpdate) {
      const { error: updateError } = await supabaseClient
        .from("receiver_profiles")
        .update({ subscription_status: currentStatus })
        .eq("user_id", userId);

      if (updateError) {
        console.error(`[check-subscription-status] Failed to update status: ${updateError.message}`);
        // Continue anyway - we still have the calculated status
      }
    }

    // Determine if subscription is valid for operations
    const validStatuses = ["trial", "active", "past_due"];
    const isValid = validStatuses.includes(currentStatus);

    // Calculate trial days remaining if applicable
    let trialDaysRemaining: number | undefined;
    if (currentStatus === "trial" && profile.trial_end_date) {
      const trialEnd = new Date(profile.trial_end_date);
      const diffMs = trialEnd.getTime() - now.getTime();
      trialDaysRemaining = Math.max(0, Math.ceil(diffMs / (1000 * 60 * 60 * 24)));
    }

    // Build response
    const response: SubscriptionResponse = {
      status: currentStatus,
      valid: isValid,
    };

    if (trialDaysRemaining !== undefined) {
      response.trial_days_remaining = trialDaysRemaining;
    }

    if (profile.subscription_end_date) {
      response.subscription_end_date = profile.subscription_end_date;
    }

    if (!isValid) {
      response.message = "Subscription expired. Please subscribe to continue receiving pings.";
    }

    console.log(`[check-subscription-status] Result for user ${userId}: status=${currentStatus}, valid=${isValid}`);

    return new Response(JSON.stringify(response), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });

  } catch (error) {
    console.error("[check-subscription-status] Error:", error);

    return new Response(
      JSON.stringify({
        success: false,
        error: error instanceof Error ? error.message : "Unknown error",
        code: "SERVER_ERROR",
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 500,
      }
    );
  }
});
