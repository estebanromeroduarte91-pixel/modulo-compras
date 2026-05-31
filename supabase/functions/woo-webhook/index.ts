// ============================================================
// TallerPro ERP — Supabase Edge Function
// Recibe webhooks de WooCommerce y sincroniza stock en ERP
//
// Eventos soportados:
//   order.completed  → descuenta stock
//   order.cancelled  → restaura stock (si venía de completed)
//   order.refunded   → restaura stock
//
// Deploy: supabase functions deploy woo-webhook
// ============================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const EMPRESA_ID = Deno.env.get('EMPRESA_ID') ?? 'default';
const WOO_SECRET = Deno.env.get('WOO_WEBHOOK_SECRET') ?? ''; // opcional pero recomendado

// Supabase con service_role (para saltarse RLS)
const sb = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

// ── Verificar firma de WooCommerce ─────────────────────────
// WooCommerce firma cada request con HMAC-SHA256 del body
// La firma viene en el header X-WC-Webhook-Signature (base64)
async function verificarFirma(req: Request, body: string): Promise<boolean> {
  if (!WOO_SECRET) return true; // Si no hay secret configurado, omitir verificación

  const firma = req.headers.get('X-WC-Webhook-Signature');
  if (!firma) return false;

  const encoder = new TextEncoder();
  const keyData = encoder.encode(WOO_SECRET);
  const msgData = encoder.encode(body);

  const cryptoKey = await crypto.subtle.importKey(
    'raw', keyData, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
  );
  const signatureBuffer = await crypto.subtle.sign('HMAC', cryptoKey, msgData);
  const signatureBase64 = btoa(String.fromCharCode(...new Uint8Array(signatureBuffer)));

  return signatureBase64 === firma;
}

// ── Handler principal ──────────────────────────────────────
Deno.serve(async (req: Request) => {
  // Solo POST
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const bodyText = await req.text();

  // Verificar firma (si WOO_SECRET está configurado)
  const firmaOk = await verificarFirma(req, bodyText);
  if (!firmaOk) {
    console.error('Firma inválida — request rechazado');
    return new Response('Unauthorized', { status: 401 });
  }

  // Parsear payload de WooCommerce
  let order: any;
  try {
    order = JSON.parse(bodyText);
  } catch {
    return new Response('Bad JSON', { status: 400 });
  }

  const evento = req.headers.get('X-WC-Webhook-Topic') ?? '';
  const orderId = order.id ?? order.number ?? '?';

  console.log(`📦 Webhook recibido | Evento: ${evento} | Pedido: ${orderId}`);

  // ── Determinar si sumar o restar stock ─────────────────────
  let delta = 0; // positivo = entrada, negativo = salida
  let tipo: string;

  if (evento === 'order.completed') {
    delta = -1;   // descuenta
    tipo  = 'woocommerce';
  } else if (evento === 'order.cancelled' || evento === 'order.refunded') {
    delta = +1;   // restaura
    tipo  = 'devolucion';
  } else {
    // Evento no relevante para stock (order.created, order.updated, etc.)
    console.log(`Evento ${evento} ignorado — no afecta stock`);
    return new Response(JSON.stringify({ ok: true, msg: 'evento ignorado' }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const lineItems: any[] = order.line_items ?? [];
  if (lineItems.length === 0) {
    return new Response(JSON.stringify({ ok: true, msg: 'sin items' }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const resultados: any[] = [];

  for (const item of lineItems) {
    const wooId    = item.product_id;        // ID del producto en WooCommerce
    const cantidad = item.quantity ?? 1;
    const nombre   = item.name ?? `Producto WC #${wooId}`;

    // Buscar producto por woocommerce_product_id
    const { data: productos, error: fetchErr } = await sb
      .from('productos')
      .select('id, nombre, stock, empresa_id')
      .eq('woocommerce_product_id', wooId)
      .eq('empresa_id', EMPRESA_ID)
      .limit(1);

    if (fetchErr) {
      console.error(`Error buscando producto WC ${wooId}:`, fetchErr.message);
      resultados.push({ wooId, ok: false, error: fetchErr.message });
      continue;
    }

    if (!productos || productos.length === 0) {
      console.warn(`⚠️  Producto WC ${wooId} (${nombre}) no encontrado en ERP — ignorado`);
      resultados.push({ wooId, nombre, ok: false, error: 'no encontrado en ERP' });
      continue;
    }

    const prod = productos[0];
    const stockAntes   = prod.stock ?? 0;
    const cambio       = delta * cantidad;      // negativo = salida
    const stockDespues = Math.max(0, stockAntes + cambio);

    // Actualizar stock
    const { error: updateErr } = await sb
      .from('productos')
      .update({ stock: stockDespues, updated_at: new Date().toISOString() })
      .eq('id', prod.id);

    if (updateErr) {
      console.error(`Error actualizando stock de ${prod.nombre}:`, updateErr.message);
      resultados.push({ wooId, nombre: prod.nombre, ok: false, error: updateErr.message });
      continue;
    }

    // Registrar movimiento
    await sb.from('movimientos_stock').insert({
      empresa_id:    EMPRESA_ID,
      producto_id:   prod.id,
      tipo,
      cantidad:      cambio,
      stock_antes:   stockAntes,
      stock_despues: stockDespues,
      referencia:    `Pedido WC #${orderId}`,
      notas:         `${item.name} × ${cantidad} — ${evento}`,
    });

    console.log(`✓ ${prod.nombre}: ${stockAntes} → ${stockDespues} (${cambio > 0 ? '+' : ''}${cambio})`);
    resultados.push({ wooId, nombre: prod.nombre, ok: true, stockAntes, stockDespues, cambio });
  }

  return new Response(JSON.stringify({ ok: true, orderId, evento, resultados }), {
    headers: { 'Content-Type': 'application/json' },
  });
});
