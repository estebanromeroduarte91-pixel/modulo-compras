// ─── SUPABASE EDGE FUNCTION: ai-query ───
// Nombre de la función: ai-query
// Variables de entorno requeridas: ANTHROPIC_API_KEY

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { pregunta, contexto, anthropic_api_key } = await req.json();

    const apiKey = Deno.env.get("ANTHROPIC_API_KEY") || anthropic_api_key;
    if (!apiKey) {
      return new Response(
        JSON.stringify({ ok: false, error: "Falta ANTHROPIC_API_KEY" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
    if (!pregunta) {
      return new Response(
        JSON.stringify({ ok: false, error: "Falta la pregunta" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const systemPrompt = `Eres un asistente de negocio integrado en un ERP chileno para talleres de reparación de celulares y tiendas de tecnología.
Tu tarea es responder preguntas sobre el negocio usando los datos que te entrega el sistema.

Reglas:
- Responde siempre en español
- Sé directo y conciso — una o dos oraciones para respuestas simples, una lista corta para respuestas complejas
- Los montos son en pesos chilenos (CLP). Usa el formato $1.234.567
- Si los datos no son suficientes para responder, dilo claramente
- No inventes datos que no estén en el contexto
- Las fechas usan formato DD-MM-YYYY o YYYY-MM-DD
- "OT" significa Orden de Trabajo (reparación de equipo)
- "VTA" significa Venta (venta de producto o servicio)
- El IVA en Chile es 19%`;

    const userMessage = `Contexto del ERP (datos actuales):
${contexto}

Pregunta del usuario: ${pregunta}`;

    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-haiku-4-5",
        max_tokens: 1024,
        system: systemPrompt,
        messages: [{ role: "user", content: userMessage }],
      }),
    });

    if (!response.ok) {
      const err = await response.text();
      return new Response(
        JSON.stringify({ ok: false, error: `Error Anthropic API: ${err}` }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const data = await response.json();
    const respuesta = data.content?.[0]?.text || "Sin respuesta";

    return new Response(JSON.stringify({ ok: true, respuesta }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (error) {
    return new Response(
      JSON.stringify({ ok: false, error: String(error?.message || error) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
