// ─── SUPABASE EDGE FUNCTION: send-email ───
// Nombre de la función: send-email

import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { to, subject, html, host, port, user, password, from, from_name } =
      await req.json();

    if (!to || !subject || !host || !user || !password) {
      return new Response(
        JSON.stringify({ ok: false, error: "Faltan parámetros requeridos" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const numPort = Number(port) || 587;
    const useTLS = numPort === 465;

    const client = new SMTPClient({
      connection: {
        hostname: host,
        port: numPort,
        tls: useTLS,
        auth: { username: user, password },
      },
    });

    // Timeout de 15s — si el SMTP no responde, devolvemos error en vez de que Supabase mate la función con 503
    const smtpTask = async () => {
      try {
        await client.send({
          from: `${from_name || "TallerPro"} <${from || user}>`,
          to: [to],
          subject,
          html: html || "",
        });
      } finally {
        await client.close().catch(() => {});
      }
    };

    const timeout = new Promise<never>((_, reject) =>
      setTimeout(() => reject(new Error("SMTP timeout: el servidor no respondió en 15s. Verifica host/puerto o usa otro proveedor SMTP.")), 15000)
    );

    await Promise.race([smtpTask(), timeout]);

    return new Response(JSON.stringify({ ok: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (error) {
    return new Response(
      JSON.stringify({ ok: false, error: String(error?.message || error) }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
