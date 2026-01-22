// Edge Function: process-payment-webhook
// Handles payment webhooks from Apple App Store Server Notifications V2
// Per plan.md Section 9.1:
// - Product ID: com.pruuf.receiver.monthly
// - Price: $2.99 USD/month
// - 15-day free trial for all receivers
// - Auto-renewable subscription managed through App Store

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { crypto } from "https://deno.land/std@0.168.0/crypto/mod.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-webhook-signature",
};

// PRUUF subscription product ID per plan.md Section 9.1
const RECEIVER_MONTHLY_PRODUCT_ID = "com.pruuf.receiver.monthly";

// Subscription status types
type SubscriptionStatus = "trial" | "active" | "past_due" | "canceled" | "expired";

interface AppleNotificationV2 {
  notificationType: string;
  subtype?: string;
  signedDate: number;
  data: {
    appAppleId: number;
    bundleId: string;
    bundleVersion: string;
    environment: string;
    signedTransactionInfo: string;
    signedRenewalInfo?: string;
  };
}

interface DecodedTransaction {
  transactionId: string;
  originalTransactionId: string;
  productId: string;
  purchaseDate: number;
  expiresDate: number;
  environment: string;
  bundleId: string;
  appAccountToken?: string;
  offerType?: number; // 1 = intro offer (free trial), 2 = promotional, 3 = offer code
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

    // Verify webhook signature
    const signature = req.headers.get("x-webhook-signature");
    const webhookSecret = Deno.env.get("WEBHOOK_SECRET");

    if (webhookSecret && signature) {
      const body = await req.text();
      const expectedSignature = await generateHmacSignature(body, webhookSecret);

      if (signature !== expectedSignature) {
        console.error("Invalid webhook signature");
        return new Response(
          JSON.stringify({ error: "Invalid signature" }),
          { status: 401, headers: corsHeaders }
        );
      }

      // Parse the verified body
      const payload = JSON.parse(body);
      return await processWebhook(supabaseClient, payload);
    }

    // For development/testing without signature verification
    const payload = await req.json();
    return await processWebhook(supabaseClient, payload);

  } catch (error: unknown) {
    console.error("Error processing payment webhook:", error);
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

async function processWebhook(supabaseClient: any, payload: any) {
  // Handle Apple App Store Server Notification V2
  if (payload.notificationType && payload.data?.signedTransactionInfo) {
    return await handleAppleWebhookV2(supabaseClient, payload as AppleNotificationV2);
  }

  // Handle legacy format or unknown
  if (payload.notificationType) {
    console.log(`Received Apple notification (legacy format): ${payload.notificationType}`);
    return new Response(
      JSON.stringify({ success: true, message: "Legacy format acknowledged" }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
    );
  }

  return new Response(
    JSON.stringify({ error: "Unknown webhook format" }),
    { status: 400, headers: corsHeaders }
  );
}

async function handleAppleWebhookV2(supabaseClient: any, payload: AppleNotificationV2) {
  const { notificationType, subtype, data } = payload;

  console.log(`Processing Apple notification: ${notificationType} ${subtype || ''}`);

  // Decode the signed transaction info (in production, verify JWS signature)
  const transaction = decodeJWSPayload(data.signedTransactionInfo);

  if (!transaction) {
    console.error("Failed to decode transaction info");
    return new Response(
      JSON.stringify({ error: "Failed to decode transaction" }),
      { status: 400, headers: corsHeaders }
    );
  }

  // Only process our receiver subscription product
  if (transaction.productId !== RECEIVER_MONTHLY_PRODUCT_ID) {
    console.log(`Ignoring notification for unknown product: ${transaction.productId}`);
    return new Response(
      JSON.stringify({ success: true, message: "Product not managed" }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
    );
  }

  // Get user ID from appAccountToken (we store user UUID here during purchase)
  const userId = transaction.appAccountToken;

  if (!userId) {
    console.error("No appAccountToken (user ID) in transaction");
    // Try to find user by original transaction ID
    const { data: profile } = await supabaseClient
      .from("receiver_profiles")
      .select("user_id")
      .eq("app_store_original_transaction_id", transaction.originalTransactionId)
      .single();

    if (!profile) {
      console.error("Could not identify user for transaction");
      return new Response(
        JSON.stringify({ success: true, message: "User not found, skipping" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
      );
    }
  }

  const targetUserId = userId || (await findUserByTransaction(supabaseClient, transaction.originalTransactionId));

  if (!targetUserId) {
    return new Response(
      JSON.stringify({ success: true, message: "User not found" }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
    );
  }

  // Handle different notification types
  switch (notificationType) {
    case "SUBSCRIBED":
      // New subscription or resubscription
      if (subtype === "INITIAL_BUY") {
        // Initial subscription purchase (including free trial start)
        const isInTrial = transaction.offerType === 1;
        await activateSubscription(supabaseClient, targetUserId, transaction, isInTrial);
      } else if (subtype === "RESUBSCRIBE") {
        // User resubscribed after expiration
        await activateSubscription(supabaseClient, targetUserId, transaction, false);
      }
      break;

    case "DID_RENEW":
      // Subscription renewed successfully
      await activateSubscription(supabaseClient, targetUserId, transaction, false);
      break;

    case "DID_CHANGE_RENEWAL_STATUS":
      // Per plan.md Section 9.3: Handle cancellation detection
      if (subtype === "AUTO_RENEW_DISABLED") {
        // User turned off auto-renew (canceled subscription)
        // Per plan.md Section 9.3:
        // - Update subscription_status = 'canceled'
        // - Access continues until end of billing period
        await handleSubscriptionCanceled(supabaseClient, targetUserId, transaction);
      } else if (subtype === "AUTO_RENEW_ENABLED") {
        // User turned on auto-renew (resubscribed)
        // Per plan.md Section 9.3: Resubscribe restores full functionality immediately
        await activateSubscription(supabaseClient, targetUserId, transaction, false);
      }
      break;

    case "EXPIRED":
      // Subscription expired
      await expireSubscription(supabaseClient, targetUserId, "expired");
      break;

    case "DID_FAIL_TO_RENEW":
      // Per plan.md Section 9.4:
      // DID_FAIL_TO_RENEW → Set status to 'past_due', notify user
      // This handles billing issues, grace period, and billing retry
      await updateSubscriptionStatus(supabaseClient, targetUserId, "past_due");
      await sendBillingIssueNotification(supabaseClient, targetUserId);

      // Log the renewal failure for auditing
      await logWebhookEvent(supabaseClient, targetUserId, "renewal_failed", {
        subtype: subtype || "none",
        transaction_id: transaction.transactionId,
        original_transaction_id: transaction.originalTransactionId,
      });
      break;

    case "GRACE_PERIOD_EXPIRED":
      // Grace period ended without successful payment
      await expireSubscription(supabaseClient, targetUserId, "expired");
      break;

    case "REFUND":
      // Per plan.md Section 9.4:
      // REFUND → Set status to 'expired', log transaction
      await expireSubscription(supabaseClient, targetUserId, "expired");
      await logRefundTransaction(supabaseClient, targetUserId, transaction);
      break;

    case "REVOKE":
      // Family sharing access revoked
      await expireSubscription(supabaseClient, targetUserId, "canceled");
      break;

    default:
      console.log(`Unhandled Apple notification type: ${notificationType}`);
  }

  return new Response(
    JSON.stringify({ success: true }),
    { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
  );
}

function decodeJWSPayload(jws: string): DecodedTransaction | null {
  try {
    // JWS format: header.payload.signature
    const parts = jws.split(".");
    if (parts.length !== 3) {
      return null;
    }

    // Decode the payload (base64url)
    const payload = parts[1];
    const decoded = atob(payload.replace(/-/g, "+").replace(/_/g, "/"));
    return JSON.parse(decoded);
  } catch (error) {
    console.error("Error decoding JWS:", error);
    return null;
  }
}

async function findUserByTransaction(supabaseClient: any, originalTransactionId: string): Promise<string | null> {
  const { data } = await supabaseClient
    .from("receiver_profiles")
    .select("user_id")
    .eq("app_store_original_transaction_id", originalTransactionId)
    .single();

  return data?.user_id || null;
}

async function activateSubscription(
  supabaseClient: any,
  userId: string,
  transaction: DecodedTransaction,
  isInTrial: boolean
) {
  const expiresAt = new Date(transaction.expiresDate).toISOString();
  const status: SubscriptionStatus = isInTrial ? "trial" : "active";

  // Call the database function to activate subscription
  const { error } = await supabaseClient.rpc("activate_appstore_subscription", {
    p_user_id: userId,
    p_transaction_id: transaction.transactionId,
    p_original_transaction_id: transaction.originalTransactionId,
    p_product_id: transaction.productId,
    p_expiration_date: expiresAt,
    p_environment: transaction.environment,
  });

  if (error) {
    console.error("Error activating subscription:", error);
    throw error;
  }

  console.log(`Activated subscription for user ${userId}, status: ${status}, expires: ${expiresAt}`);
}

async function expireSubscription(
  supabaseClient: any,
  userId: string,
  reason: "expired" | "canceled"
) {
  const { error } = await supabaseClient.rpc("expire_appstore_subscription", {
    p_user_id: userId,
    p_reason: reason,
  });

  if (error) {
    console.error("Error expiring subscription:", error);
    throw error;
  }

  console.log(`Subscription ${reason} for user ${userId}`);
}

async function updateSubscriptionStatus(
  supabaseClient: any,
  userId: string,
  status: SubscriptionStatus
) {
  const { error } = await supabaseClient
    .from("receiver_profiles")
    .update({
      subscription_status: status,
      updated_at: new Date().toISOString(),
    })
    .eq("user_id", userId);

  if (error) {
    console.error("Error updating subscription status:", error);
    throw error;
  }

  console.log(`Updated subscription status for user ${userId} to ${status}`);
}

// Per plan.md Section 9.3: Handle subscription cancellation
// - Update subscription_status = 'canceled'
// - Access continues until end of billing period
// - App shows message: "Your subscription will end on [date]"
async function handleSubscriptionCanceled(
  supabaseClient: any,
  userId: string,
  transaction: DecodedTransaction
) {
  const expiresAt = new Date(transaction.expiresDate).toISOString();

  const { error } = await supabaseClient
    .from("receiver_profiles")
    .update({
      subscription_status: "canceled",
      // Keep the subscription_end_date so access continues until then
      subscription_end_date: expiresAt,
      updated_at: new Date().toISOString(),
    })
    .eq("user_id", userId);

  if (error) {
    console.error("Error handling subscription cancellation:", error);
    throw error;
  }

  // Log audit event
  await supabaseClient.from("audit_logs").insert({
    user_id: userId,
    action: "subscription_canceled",
    resource_type: "receiver_profile",
    details: {
      cancellation_date: new Date().toISOString(),
      access_until: expiresAt,
    },
  });

  // Send notification to user about cancellation
  await supabaseClient.from("notifications").insert({
    user_id: userId,
    title: "Subscription Canceled",
    body: `Your subscription has been canceled. You'll have access until ${new Date(transaction.expiresDate).toLocaleDateString()}.`,
    type: "payment_reminder",
    sent_at: new Date().toISOString(),
    delivery_status: "sent",
  });

  console.log(`Subscription canceled for user ${userId}, access until ${expiresAt}`);
}

async function sendBillingIssueNotification(supabaseClient: any, userId: string) {
  const { error } = await supabaseClient.from("notifications").insert({
    user_id: userId,
    title: "Payment Issue",
    body: "There's an issue with your subscription payment. Please update your payment method in the App Store to continue receiving notifications.",
    type: "payment_reminder",
    sent_at: new Date().toISOString(),
    delivery_status: "sent",
  });

  if (error) {
    console.error("Error sending billing notification:", error);
  }

  console.log(`Sent billing issue notification to user ${userId}`);
}

async function generateHmacSignature(body: string, secret: string): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(body)
  );

  return Array.from(new Uint8Array(signature))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// Per plan.md Section 9.4: Log webhook events for auditing
async function logWebhookEvent(
  supabaseClient: any,
  userId: string,
  eventType: string,
  details: Record<string, any>
) {
  const { error } = await supabaseClient.from("audit_logs").insert({
    user_id: userId,
    action: `webhook_${eventType}`,
    resource_type: "subscription",
    details: {
      ...details,
      timestamp: new Date().toISOString(),
    },
  });

  if (error) {
    console.error(`Error logging webhook event ${eventType}:`, error);
  }

  console.log(`Logged webhook event: ${eventType} for user ${userId}`);
}

// Per plan.md Section 9.4: REFUND → log transaction
async function logRefundTransaction(
  supabaseClient: any,
  userId: string,
  transaction: DecodedTransaction
) {
  // Log to audit_logs for transaction history
  const { error: auditError } = await supabaseClient.from("audit_logs").insert({
    user_id: userId,
    action: "subscription_refunded",
    resource_type: "subscription",
    details: {
      transaction_id: transaction.transactionId,
      original_transaction_id: transaction.originalTransactionId,
      product_id: transaction.productId,
      refund_date: new Date().toISOString(),
      environment: transaction.environment,
    },
  });

  if (auditError) {
    console.error("Error logging refund to audit_logs:", auditError);
  }

  // Send notification to user about the refund
  const { error: notifError } = await supabaseClient.from("notifications").insert({
    user_id: userId,
    title: "Subscription Refunded",
    body: "Your subscription has been refunded and your access has been revoked. Contact support if you have questions.",
    type: "payment_reminder",
    sent_at: new Date().toISOString(),
    delivery_status: "sent",
  });

  if (notifError) {
    console.error("Error sending refund notification:", notifError);
  }

  console.log(`Logged refund transaction ${transaction.transactionId} for user ${userId}`);
}
