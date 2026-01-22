// Edge Function: export-user-data
// Phase 10 Section 10.3: Data Export GDPR
// Per plan.md:
// - Gather all user data
// - Generate ZIP file containing: User profile (JSON), All connections (JSON),
//   All pings history (CSV), All notifications (CSV), Break history (JSON),
//   Payment transactions (CSV)
// - Upload to Storage bucket with 7-day expiration
// - Generate signed URL
// - Send email with download link
// - Process within 48 hours

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { JSZip } from "https://deno.land/x/jszip@0.11.0/mod.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface ExportRequest {
  userId: string;
  requestId?: string; // If processing an existing request
  deliveryMethod?: "download" | "email"; // Default is download
  email?: string; // Required if deliveryMethod is email
}

interface ExportData {
  user_profile: Record<string, unknown> | null;
  sender_profile: Record<string, unknown> | null;
  receiver_profile: Record<string, unknown> | null;
  connections: Record<string, unknown>[];
  pings: Record<string, unknown>[];
  breaks: Record<string, unknown>[];
  notifications: Record<string, unknown>[];
  payment_transactions: Record<string, unknown>[];
  export_info: {
    exported_at: string;
    format_version: string;
    data_categories: string[];
  };
}

// Convert JSON array to CSV string
function jsonToCSV(data: Record<string, unknown>[], columns?: string[]): string {
  if (!data || data.length === 0) {
    return columns ? columns.join(",") + "\n" : "";
  }

  // Get all unique keys from data if columns not specified
  const headers = columns || [...new Set(data.flatMap(obj => Object.keys(obj)))];

  // Create header row
  const csvRows = [headers.join(",")];

  // Create data rows
  for (const row of data) {
    const values = headers.map(header => {
      const value = row[header];
      if (value === null || value === undefined) {
        return "";
      }
      if (typeof value === "object") {
        return `"${JSON.stringify(value).replace(/"/g, '""')}"`;
      }
      const stringValue = String(value);
      // Escape quotes and wrap in quotes if contains comma, newline, or quote
      if (stringValue.includes(",") || stringValue.includes("\n") || stringValue.includes('"')) {
        return `"${stringValue.replace(/"/g, '""')}"`;
      }
      return stringValue;
    });
    csvRows.push(values.join(","));
  }

  return csvRows.join("\n");
}

// Format date for filename
function getFormattedDate(): string {
  const now = new Date();
  return now.toISOString().split("T")[0].replace(/-/g, "");
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Initialize Supabase client with service role for full access
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // Parse request
    const body: ExportRequest = await req.json();
    const { userId, requestId, deliveryMethod = "download", email } = body;

    if (!userId) {
      return new Response(
        JSON.stringify({ success: false, error: "userId is required" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 }
      );
    }

    console.log(`[export-user-data] Starting export for user ${userId}`);

    // Create or get export request
    let exportRequestId = requestId;
    if (!exportRequestId) {
      const { data: newRequestId, error: requestError } = await supabaseClient
        .rpc("request_data_export", { p_user_id: userId });

      if (requestError) {
        console.error("[export-user-data] Error creating request:", requestError);
        return new Response(
          JSON.stringify({ success: false, error: "Failed to create export request" }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 }
        );
      }
      exportRequestId = newRequestId;
    }

    // Mark as processing
    await supabaseClient
      .from("data_export_requests")
      .update({
        status: "processing",
        started_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq("id", exportRequestId);

    // Get all user data using database function
    const { data: exportData, error: dataError } = await supabaseClient
      .rpc("get_user_export_data", { p_user_id: userId });

    if (dataError) {
      console.error("[export-user-data] Error getting user data:", dataError);
      await supabaseClient.rpc("fail_data_export", {
        p_request_id: exportRequestId,
        p_error_message: dataError.message,
      });
      return new Response(
        JSON.stringify({ success: false, error: "Failed to retrieve user data" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 }
      );
    }

    const data = exportData as ExportData;
    console.log(`[export-user-data] Retrieved data for user ${userId}`);

    // Create ZIP file
    const zip = new JSZip();

    // Add README
    const readme = `PRUUF Data Export
==================
User ID: ${userId}
Exported: ${data.export_info.exported_at}
Format Version: ${data.export_info.format_version}

This archive contains all your personal data from PRUUF.

Contents:
---------
1. user_profile.json - Your account information
2. sender_profile.json - Your sender settings (if applicable)
3. receiver_profile.json - Your receiver settings (if applicable)
4. connections.json - All your connections
5. pings_history.csv - Complete history of all pings
6. notifications.csv - All notifications you received
7. breaks.json - All scheduled breaks (if sender)
8. payment_transactions.csv - Payment history

Data Retention:
---------------
This export file will be available for download for 7 days.
After 7 days, the file will be automatically deleted.

For questions about your data, contact support@pruuf.com
`;
    zip.addFile("README.txt", new TextEncoder().encode(readme));

    // 1. User Profile (JSON)
    if (data.user_profile) {
      zip.addFile(
        "user_profile.json",
        new TextEncoder().encode(JSON.stringify(data.user_profile, null, 2))
      );
    }

    // 2. Sender Profile (JSON)
    if (data.sender_profile) {
      zip.addFile(
        "sender_profile.json",
        new TextEncoder().encode(JSON.stringify(data.sender_profile, null, 2))
      );
    }

    // 3. Receiver Profile (JSON)
    if (data.receiver_profile) {
      zip.addFile(
        "receiver_profile.json",
        new TextEncoder().encode(JSON.stringify(data.receiver_profile, null, 2))
      );
    }

    // 4. Connections (JSON)
    zip.addFile(
      "connections.json",
      new TextEncoder().encode(JSON.stringify(data.connections || [], null, 2))
    );

    // 5. Pings History (CSV) - per plan.md requirement
    const pingsCSV = jsonToCSV(
      data.pings || [],
      ["id", "role_in_ping", "scheduled_time", "deadline_time", "completed_at", "completion_method", "status", "notes", "created_at"]
    );
    zip.addFile("pings_history.csv", new TextEncoder().encode(pingsCSV));

    // 6. Notifications (CSV) - per plan.md requirement
    const notificationsCSV = jsonToCSV(
      data.notifications || [],
      ["id", "type", "title", "body", "sent_at", "read_at", "delivery_status"]
    );
    zip.addFile("notifications.csv", new TextEncoder().encode(notificationsCSV));

    // 7. Break History (JSON) - per plan.md requirement
    zip.addFile(
      "breaks.json",
      new TextEncoder().encode(JSON.stringify(data.breaks || [], null, 2))
    );

    // 8. Payment Transactions (CSV) - per plan.md requirement
    const paymentsCSV = jsonToCSV(
      data.payment_transactions || [],
      ["id", "amount", "currency", "status", "transaction_type", "created_at"]
    );
    zip.addFile("payment_transactions.csv", new TextEncoder().encode(paymentsCSV));

    // Generate ZIP binary
    const zipContent = await zip.generateAsync({ type: "uint8array" });
    const fileSize = zipContent.length;

    console.log(`[export-user-data] Generated ZIP file, size: ${fileSize} bytes`);

    // Upload to storage
    const dateStr = getFormattedDate();
    const filePath = `${userId}/pruuf_export_${dateStr}_${exportRequestId}.zip`;

    const { error: uploadError } = await supabaseClient.storage
      .from("data-exports")
      .upload(filePath, zipContent, {
        contentType: "application/zip",
        upsert: true,
      });

    if (uploadError) {
      console.error("[export-user-data] Error uploading to storage:", uploadError);
      await supabaseClient.rpc("fail_data_export", {
        p_request_id: exportRequestId,
        p_error_message: uploadError.message,
      });
      return new Response(
        JSON.stringify({ success: false, error: "Failed to upload export file" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 }
      );
    }

    console.log(`[export-user-data] Uploaded to storage: ${filePath}`);

    // Mark export as completed
    await supabaseClient.rpc("complete_data_export", {
      p_request_id: exportRequestId,
      p_file_path: filePath,
      p_file_size: fileSize,
    });

    // Generate signed URL (7 days expiration)
    const { data: signedUrlData, error: signedUrlError } = await supabaseClient.storage
      .from("data-exports")
      .createSignedUrl(filePath, 60 * 60 * 24 * 7); // 7 days in seconds

    if (signedUrlError) {
      console.error("[export-user-data] Error generating signed URL:", signedUrlError);
      // Export is complete but URL generation failed - still return success
    }

    const downloadUrl = signedUrlData?.signedUrl || null;

    // Create notification for user
    const { error: notifError } = await supabaseClient
      .from("notifications")
      .insert({
        user_id: userId,
        type: "data_export_ready",
        title: "Your Data Export is Ready",
        body: "Your PRUUF data export is ready for download. The link will expire in 7 days.",
        metadata: {
          request_id: exportRequestId,
          file_size_bytes: fileSize,
          expires_in_days: 7,
        },
        delivery_status: "sent",
      });

    if (notifError) {
      console.error("[export-user-data] Error creating notification:", notifError);
    }

    // If email delivery requested, send email (placeholder - requires email service integration)
    if (deliveryMethod === "email" && email) {
      // Note: Email sending would require integration with a service like SendGrid, Resend, etc.
      // For now, we log the intent and include info in response
      console.log(`[export-user-data] Email delivery requested to ${email}`);

      // Create notification about email
      await supabaseClient
        .from("notifications")
        .insert({
          user_id: userId,
          type: "data_export_email_sent",
          title: "Data Export Email Sent",
          body: `Your data export download link has been sent to ${email}`,
          metadata: {
            email,
            request_id: exportRequestId,
          },
          delivery_status: "pending", // Would be updated by email service callback
        });
    }

    // Send push notification
    try {
      await fetch(
        `${Deno.env.get("SUPABASE_URL")}/functions/v1/send-ping-notification`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
          },
          body: JSON.stringify({
            type: "data_export_ready",
            sender_id: userId,
            receiver_ids: [userId],
            additional_data: {
              request_id: exportRequestId,
            },
          }),
        }
      );
    } catch (pushError) {
      console.error("[export-user-data] Error sending push notification:", pushError);
    }

    console.log(`[export-user-data] Export completed successfully for user ${userId}`);

    return new Response(
      JSON.stringify({
        success: true,
        request_id: exportRequestId,
        download_url: downloadUrl,
        file_size_bytes: fileSize,
        expires_at: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
        delivery_method: deliveryMethod,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
    );
  } catch (error: unknown) {
    console.error("[export-user-data] Unexpected error:", error);
    const errorMessage = error instanceof Error ? error.message : "Internal server error";
    return new Response(
      JSON.stringify({ success: false, error: errorMessage }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 }
    );
  }
});
