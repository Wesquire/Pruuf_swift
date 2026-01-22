// Edge Function: send-apns-notification
// Sends push notifications via Apple Push Notification service (APNs) HTTP/2 API
// Phase 8 Section 8.1: Push Notification Setup

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import * as jose from "https://deno.land/x/jose@v4.14.4/index.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// APNs Configuration
interface APNsConfig {
  teamId: string;
  keyId: string;
  privateKey: string;
  bundleId: string;
  production: boolean;
}

// Notification request payload (user_ids mode - looks up tokens from database)
interface NotificationRequest {
  user_ids: string[];
  title: string;
  body: string;
  type: string;
  data?: Record<string, unknown>;
  badge?: number;
  sound?: string | null;
  category?: string;
  thread_id?: string;
  priority?: "high" | "normal";
}

// Direct device token notification (for verification codes during auth)
interface DirectTokenNotificationRequest {
  deviceToken: string;
  title: string;
  body: string;
  data?: Record<string, unknown>;
  badge?: number;
  sound?: string | null;
  priority?: "high" | "normal";
}

// APNs response types
interface APNsResponse {
  success: boolean;
  token: string;
  statusCode?: number;
  reason?: string;
}

// Generate JWT for APNs authentication
async function generateAPNsJWT(config: APNsConfig): Promise<string> {
  const privateKey = await jose.importPKCS8(config.privateKey, "ES256");

  const jwt = await new jose.SignJWT({})
    .setProtectedHeader({
      alg: "ES256",
      kid: config.keyId,
    })
    .setIssuer(config.teamId)
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(privateKey);

  return jwt;
}

// Get APNs host URL based on environment
function getAPNsHost(production: boolean): string {
  return production
    ? "https://api.push.apple.com"
    : "https://api.sandbox.push.apple.com";
}

// Build APNs payload
function buildAPNsPayload(
  notification: NotificationRequest,
  token: string
): Record<string, unknown> {
  const aps: Record<string, unknown> = {
    alert: {
      title: notification.title,
      body: notification.body,
    },
  };

  if (notification.sound !== undefined) {
    if (notification.sound !== null && notification.sound !== "") {
      aps.sound = notification.sound;
    }
  } else {
    aps.sound = "default";
  }

  // Add badge if specified
  if (notification.badge !== undefined) {
    aps.badge = notification.badge;
  }

  // Add category for actionable notifications
  if (notification.category) {
    aps.category = notification.category;
  }

  // Add thread-id for notification grouping
  if (notification.thread_id) {
    aps["thread-id"] = notification.thread_id;
  }

  // Set content-available for background notifications
  if (notification.priority === "high") {
    aps["content-available"] = 1;
  }

  // Build full payload
  const payload: Record<string, unknown> = {
    aps,
    type: notification.type,
  };

  // Add custom data
  if (notification.data) {
    Object.assign(payload, notification.data);
  }

  return payload;
}

// Send notification to a single device via APNs
async function sendToDevice(
  token: string,
  payload: Record<string, unknown>,
  config: APNsConfig,
  jwt: string,
  priority: "high" | "normal" = "high"
): Promise<APNsResponse> {
  const host = getAPNsHost(config.production);
  const url = `${host}/3/device/${token}`;

  const headers = {
    "authorization": `bearer ${jwt}`,
    "apns-topic": config.bundleId,
    "apns-push-type": "alert",
    "apns-priority": priority === "high" ? "10" : "5",
    "content-type": "application/json",
  };

  try {
    const response = await fetch(url, {
      method: "POST",
      headers,
      body: JSON.stringify(payload),
    });

    if (response.status === 200) {
      return { success: true, token };
    }

    // Handle APNs error responses
    const errorBody = await response.json().catch(() => ({}));
    const reason = errorBody.reason || `HTTP ${response.status}`;

    console.error(`APNs error for token ${token.substring(0, 8)}...: ${reason}`);

    return {
      success: false,
      token,
      statusCode: response.status,
      reason,
    };
  } catch (error: unknown) {
    const errorMessage = error instanceof Error ? error.message : "Unknown error";
    console.error(`Failed to send to APNs: ${errorMessage}`);
    return {
      success: false,
      token,
      reason: errorMessage,
    };
  }
}

// Check if token should be invalidated based on APNs error
function shouldInvalidateToken(reason: string | undefined): boolean {
  const invalidTokenReasons = [
    "BadDeviceToken",
    "Unregistered",
    "DeviceTokenNotForTopic",
    "ExpiredToken",
  ];
  return reason !== undefined && invalidTokenReasons.includes(reason);
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Get APNs configuration from environment
    const config: APNsConfig = {
      teamId: Deno.env.get("APNS_TEAM_ID") ?? "",
      keyId: Deno.env.get("APNS_KEY_ID") ?? "",
      privateKey: Deno.env.get("APNS_PRIVATE_KEY")?.replace(/\\n/g, "\n") ?? "",
      bundleId: Deno.env.get("APNS_BUNDLE_ID") ?? "com.pruuf.app",
      production: Deno.env.get("APNS_PRODUCTION") === "true",
    };

    // Validate configuration
    if (!config.teamId || !config.keyId || !config.privateKey) {
      throw new Error("APNs configuration is incomplete. Required: APNS_TEAM_ID, APNS_KEY_ID, APNS_PRIVATE_KEY");
    }

    // Parse request body
    const requestBody = await req.json();

    // Check if this is a direct device token request (for verification codes)
    // or a user_ids request (for general notifications)
    const isDirectTokenRequest = "deviceToken" in requestBody && requestBody.deviceToken;

    if (isDirectTokenRequest) {
      // Direct device token mode - for verification code delivery
      const directRequest = requestBody as DirectTokenNotificationRequest;

      if (!directRequest.title || !directRequest.body) {
        throw new Error("title and body are required");
      }

      // Generate APNs JWT
      const jwt = await generateAPNsJWT(config);

      // Build payload for direct token notification
      const payload: Record<string, unknown> = {
        aps: {
          alert: {
            title: directRequest.title,
            body: directRequest.body,
          },
          sound: directRequest.sound !== undefined ? directRequest.sound : "default",
        },
        type: "verification",
      };

      // Add badge if specified
      if (directRequest.badge !== undefined) {
        (payload.aps as Record<string, unknown>).badge = directRequest.badge;
      }

      // Add custom data
      if (directRequest.data) {
        Object.assign(payload, directRequest.data);
      }

      // Send directly to the provided device token
      const result = await sendToDevice(
        directRequest.deviceToken,
        payload,
        config,
        jwt,
        directRequest.priority || "high"
      );

      return new Response(
        JSON.stringify({
          success: result.success,
          messageId: result.success ? `direct-${Date.now()}` : null,
          error: result.reason || null,
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: result.success ? 200 : 400,
        }
      );
    }

    // User IDs mode - standard notification flow
    const notification = requestBody as NotificationRequest;

    if (!notification.user_ids || notification.user_ids.length === 0) {
      throw new Error("user_ids is required");
    }

    if (!notification.title || !notification.body) {
      throw new Error("title and body are required");
    }

    // Initialize Supabase client with service role
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // Get device tokens for the specified users
    const { data: tokens, error: tokensError } = await supabaseClient.rpc(
      "get_device_tokens_for_users",
      { p_user_ids: notification.user_ids }
    );

    if (tokensError) {
      throw tokensError;
    }

    if (!tokens || tokens.length === 0) {
      return new Response(
        JSON.stringify({
          success: true,
          message: "No device tokens found for specified users",
          sent: 0,
          failed: 0,
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 200,
        }
      );
    }

    // Generate APNs JWT
    const jwt = await generateAPNsJWT(config);

    // Send notifications to all devices
    const results: APNsResponse[] = [];
    const tokensToInvalidate: string[] = [];

    for (const tokenInfo of tokens) {
      // Determine if this is a production or sandbox token
      const isProduction = tokenInfo.platform === "ios";

      // Only send if the token matches the current environment
      if (isProduction !== config.production) {
        console.log(`Skipping token for ${tokenInfo.platform} (env: ${config.production ? "production" : "sandbox"})`);
        continue;
      }

      const payload = buildAPNsPayload(notification, tokenInfo.device_token);
      const result = await sendToDevice(
        tokenInfo.device_token,
        payload,
        config,
        jwt,
        notification.priority
      );

      results.push(result);

      // Track tokens that need to be invalidated
      if (!result.success && shouldInvalidateToken(result.reason)) {
        tokensToInvalidate.push(tokenInfo.device_token);
      }
    }

    // Invalidate failed tokens
    for (const token of tokensToInvalidate) {
      const { error: invalidateError } = await supabaseClient.rpc(
        "invalidate_device_token",
        { p_device_token: token, p_reason: "apns_delivery_failure" }
      );

      if (invalidateError) {
        console.error(`Failed to invalidate token: ${invalidateError.message}`);
      }
    }

    // Update last_used_at for successful tokens
    const successfulTokens = results.filter((r) => r.success).map((r) => r.token);
    if (successfulTokens.length > 0) {
      await supabaseClient
        .from("device_tokens")
        .update({ last_used_at: new Date().toISOString() })
        .in("device_token", successfulTokens);
    }

    // Store notification records for in-app notification center
    const notificationRecords = notification.user_ids.map((userId) => ({
      user_id: userId,
      type: notification.type,
      title: notification.title,
      body: notification.body,
      metadata: notification.data || {},
      delivery_status: results.some((r) => r.success && tokens.find((t: { user_id: string; device_token: string }) =>
        t.device_token === r.token && t.user_id === userId
      ))
        ? "sent"
        : "failed",
    }));

    await supabaseClient.from("notifications").insert(notificationRecords);

    // Return results
    const successCount = results.filter((r) => r.success).length;
    const failedCount = results.filter((r) => !r.success).length;

    return new Response(
      JSON.stringify({
        success: true,
        sent: successCount,
        failed: failedCount,
        invalidated: tokensToInvalidate.length,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      }
    );
  } catch (error: unknown) {
    console.error("Error sending APNs notification:", error);
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
