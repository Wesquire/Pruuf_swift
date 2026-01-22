// Edge Function: cleanup-expired-data
// CRON job for cleaning up expired data
// Phase 12 Section 12.2: Edge Function Specifications
//
// Called by Supabase cron scheduler
// Cleans up:
// - Expired unique codes
// - Old notifications (>90 days)
// - Old audit logs (>365 days, configurable)
// - Completed/canceled breaks (optional retention; disabled by default)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface CleanupConfig {
  // Days to keep notifications (default: 90)
  notification_retention_days?: number;
  // Days to keep audit logs (default: 365)
  audit_log_retention_days?: number;
  // Days to keep completed breaks (optional; when omitted, breaks are retained)
  completed_breaks_retention_days?: number;
  // Whether to perform a dry run (default: false)
  dry_run?: boolean;
}

interface CleanupResult {
  expired_codes_deleted: number;
  old_notifications_deleted: number;
  old_audit_logs_deleted: number;
  old_breaks_deleted: number;
  errors: string[];
  dry_run: boolean;
  timestamp: string;
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

    // Parse optional config from request body
    let config: CleanupConfig = {};
    if (req.method === "POST") {
      try {
        config = await req.json();
      } catch {
        // Empty body is fine - use defaults
      }
    }

    const notificationRetentionDays = config.notification_retention_days ?? 90;
    const auditLogRetentionDays = config.audit_log_retention_days ?? 365;
    const completedBreaksRetentionDays = config.completed_breaks_retention_days;
    const dryRun = config.dry_run ?? false;

    console.log(`[cleanup-expired-data] Starting cleanup (dry_run=${dryRun})`);
    const breaksConfigLabel = completedBreaksRetentionDays === undefined
      ? "disabled"
      : `${completedBreaksRetentionDays}d`;
    console.log(`[cleanup-expired-data] Config: notifications=${notificationRetentionDays}d, audit=${auditLogRetentionDays}d, breaks=${breaksConfigLabel}`);

    const now = new Date();
    const errors: string[] = [];
    const result: CleanupResult = {
      expired_codes_deleted: 0,
      old_notifications_deleted: 0,
      old_audit_logs_deleted: 0,
      old_breaks_deleted: 0,
      errors: [],
      dry_run: dryRun,
      timestamp: now.toISOString(),
    };

    // 1. Delete expired unique codes
    try {
      const expiredCodesQuery = supabaseClient
        .from("unique_codes")
        .select("id", { count: "exact" })
        .lt("expires_at", now.toISOString())
        .not("expires_at", "is", null);

      const { count: expiredCodesCount } = await expiredCodesQuery;

      if (!dryRun && expiredCodesCount && expiredCodesCount > 0) {
        const { error: deleteError } = await supabaseClient
          .from("unique_codes")
          .delete()
          .lt("expires_at", now.toISOString())
          .not("expires_at", "is", null);

        if (deleteError) throw deleteError;
      }

      result.expired_codes_deleted = expiredCodesCount ?? 0;
      console.log(`[cleanup-expired-data] Expired codes: ${result.expired_codes_deleted}`);
    } catch (err) {
      const msg = `Failed to cleanup expired codes: ${err instanceof Error ? err.message : "Unknown error"}`;
      errors.push(msg);
      console.error(`[cleanup-expired-data] ${msg}`);
    }

    // 2. Delete old notifications
    try {
      const notificationCutoff = new Date(now.getTime() - notificationRetentionDays * 24 * 60 * 60 * 1000);

      const { count: oldNotificationsCount } = await supabaseClient
        .from("notifications")
        .select("id", { count: "exact" })
        .lt("sent_at", notificationCutoff.toISOString());

      if (!dryRun && oldNotificationsCount && oldNotificationsCount > 0) {
        const { error: deleteError } = await supabaseClient
          .from("notifications")
          .delete()
          .lt("sent_at", notificationCutoff.toISOString());

        if (deleteError) throw deleteError;
      }

      result.old_notifications_deleted = oldNotificationsCount ?? 0;
      console.log(`[cleanup-expired-data] Old notifications: ${result.old_notifications_deleted}`);
    } catch (err) {
      const msg = `Failed to cleanup old notifications: ${err instanceof Error ? err.message : "Unknown error"}`;
      errors.push(msg);
      console.error(`[cleanup-expired-data] ${msg}`);
    }

    // 3. Delete old audit logs
    try {
      const auditLogCutoff = new Date(now.getTime() - auditLogRetentionDays * 24 * 60 * 60 * 1000);

      const { count: oldAuditLogsCount } = await supabaseClient
        .from("audit_logs")
        .select("id", { count: "exact" })
        .lt("created_at", auditLogCutoff.toISOString());

      if (!dryRun && oldAuditLogsCount && oldAuditLogsCount > 0) {
        const { error: deleteError } = await supabaseClient
          .from("audit_logs")
          .delete()
          .lt("created_at", auditLogCutoff.toISOString());

        if (deleteError) throw deleteError;
      }

      result.old_audit_logs_deleted = oldAuditLogsCount ?? 0;
      console.log(`[cleanup-expired-data] Old audit logs: ${result.old_audit_logs_deleted}`);
    } catch (err) {
      const msg = `Failed to cleanup old audit logs: ${err instanceof Error ? err.message : "Unknown error"}`;
      errors.push(msg);
      console.error(`[cleanup-expired-data] ${msg}`);
    }

    // 4. Delete old completed/canceled breaks (optional)
    if (completedBreaksRetentionDays !== undefined) {
      try {
        const breaksCutoff = new Date(now.getTime() - completedBreaksRetentionDays * 24 * 60 * 60 * 1000);

        const { count: oldBreaksCount } = await supabaseClient
          .from("breaks")
          .select("id", { count: "exact" })
          .in("status", ["completed", "canceled"])
          .lt("end_date", breaksCutoff.toISOString().split("T")[0]);

        if (!dryRun && oldBreaksCount && oldBreaksCount > 0) {
          const { error: deleteError } = await supabaseClient
            .from("breaks")
            .delete()
            .in("status", ["completed", "canceled"])
            .lt("end_date", breaksCutoff.toISOString().split("T")[0]);

          if (deleteError) throw deleteError;
        }

        result.old_breaks_deleted = oldBreaksCount ?? 0;
        console.log(`[cleanup-expired-data] Old breaks: ${result.old_breaks_deleted}`);
      } catch (err) {
        const msg = `Failed to cleanup old breaks: ${err instanceof Error ? err.message : "Unknown error"}`;
        errors.push(msg);
        console.error(`[cleanup-expired-data] ${msg}`);
      }
    } else {
      console.log("[cleanup-expired-data] Break cleanup disabled (retaining all breaks)");
    }

    result.errors = errors;

    // Log the cleanup run
    if (!dryRun) {
      await supabaseClient.from("audit_logs").insert({
        user_id: null, // System action
        action: "cleanup_expired_data",
        resource_type: "system",
        details: {
          expired_codes_deleted: result.expired_codes_deleted,
          old_notifications_deleted: result.old_notifications_deleted,
          old_audit_logs_deleted: result.old_audit_logs_deleted,
          old_breaks_deleted: result.old_breaks_deleted,
          errors: errors,
          config: {
            notification_retention_days: notificationRetentionDays,
            audit_log_retention_days: auditLogRetentionDays,
            completed_breaks_retention_days: completedBreaksRetentionDays ?? "disabled",
          },
        },
      });
    }

    const totalDeleted = result.expired_codes_deleted +
                         result.old_notifications_deleted +
                         result.old_audit_logs_deleted +
                         result.old_breaks_deleted;

    console.log(`[cleanup-expired-data] Cleanup complete. Total items ${dryRun ? "would be" : ""} deleted: ${totalDeleted}`);

    return new Response(JSON.stringify({
      success: errors.length === 0,
      ...result,
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });

  } catch (error) {
    console.error("[cleanup-expired-data] Error:", error);

    return new Response(
      JSON.stringify({
        success: false,
        error: error instanceof Error ? error.message : "Unknown error",
        timestamp: new Date().toISOString(),
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 500,
      }
    );
  }
});
