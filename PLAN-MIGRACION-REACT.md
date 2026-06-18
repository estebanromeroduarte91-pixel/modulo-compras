# Plan de Migración a React — ERP Steve Docs

> Documento guía para migrar el ERP de **un solo archivo HTML/JS (vanilla)** a **React**, sin perder datos ni apagar el producto actual. Sirve para el programador y para ejecutar módulo por módulo con un modelo de IA (ej: Sonnet 4.6).

---

## 0. Resumen para el dueño del producto

- **No se pierde nada de datos.** El backend (Supabase) se queda **idéntico**: misma base de datos, mismos usuarios, mismos correos. Solo se rehace la "cara" (las pantallas).
- **Se hace por módulos**, no todo de golpe. El ERP actual sigue vivo hasta que la versión React esté completa.
- **La lógica se reutiliza** (cálculos, Excel, armado de correos), no se reinventa.
- **Regla de oro:** en esta migración se cambia SOLO la interfaz a React. **NO se rediseña la base de datos.** Eso es un proyecto aparte y posterior (ver §10).

---

## 1. Principios de la migración

1. **UI primero, datos igual.** Se reescribe la interfaz en React reutilizando la MISMA tabla `erp_data` de Supabase. Cero migración de datos = cero riesgo de pérdida.
2. **Convivencia.** El ERP actual (Netlify) sigue en producción. La versión React se desarrolla en paralelo, conectada al MISMO Supabase, viendo datos reales.
3. **Módulo por módulo.** Se migra, se prueba a paridad, y recién ahí el siguiente. Si algo falla, afecta solo a ese módulo.
4. **Switch al final.** Cuando React iguala todo lo del actual, se apunta el dominio a la nueva versión. La vieja queda de respaldo.

---

## 2. Stack destino

| Capa | Herramienta | Por qué |
|---|---|---|
| Build/dev | **Vite** | Rápido, simple, estándar para SPA |
| UI | **React 18 + TypeScript** | Tipos = menos bugs en un ERP con muchos datos |
| Ruteo | **React Router** | Navegación entre módulos |
| Datos/cache | **TanStack Query (React Query)** | Reemplaza el `_dbCache` + debounce manual |
| Backend | **Supabase** (el mismo) | Sin cambios: DB, Auth, Edge Functions, Storage |
| Componentes | **shadcn/ui** + **Tailwind CSS** | Botones, modales, tablas listos y consistentes |
| Tablas/grillas | **TanStack Table** | Grillas de ERP (ordenar, filtrar, paginar) |
| Formularios | **React Hook Form + Zod** | Formularios y validación robustos |
| Gráficos | **Recharts** (o seguir con Chart.js) | Dashboard y estadísticas |
| Excel | **SheetJS (xlsx)** | Ya se usa; se reutiliza igual |

> No se necesita Next.js: la app es un panel detrás de login, sin necesidad de SSR/SEO. Vite SPA es lo correcto y más simple.

---

## 3. Estructura de carpetas (propuesta)

```
src/
  main.tsx                 # punto de entrada
  App.tsx                  # router + layout
  lib/
    supabase.ts            # cliente Supabase (config de §2 de auth/persistencia)
    db.ts                  # capa de acceso a erp_data (get/set por clave) → ver §4
    queries.ts             # hooks de TanStack Query (useProductos, useOrders, ...)
    email.ts               # invocación de Edge Functions (send-email, manage-domain)
    excel.ts               # import/export con SheetJS
    format.ts              # fmt$ , RUT, fechas, etc.
  context/
    AuthContext.tsx        # usuario, empresaId, rol, sucursal (branchContext)
  components/
    ui/                    # shadcn (button, dialog, input, table...)
    layout/                # Sidebar, Topbar, Shell
    shared/                # DataTable, Money, Badge, Modal, FormField...
  modules/
    dashboard/
    ventas/                # POS, ventas, caja
    taller/                # órdenes, equipos, inspección, traslados, settings
    contactos/             # clientes, proveedores
    inventario/            # productos, bodegas, movimientos, categorías, kits, OC
    contabilidad/          # plan de cuentas, asientos
    gastos/
    estadisticas/
    config/                # seguimiento, smtp, dominio, términos, mensajes, cargos, accesos
  types/
    index.ts               # tipos: Producto, Orden, Cliente, Venta, ...
```

---

## 4. Capa de datos (lo más importante de la migración)

El ERP actual guarda todo en una sola tabla Supabase:

```
erp_data ( empresa_id, clave, datos jsonb, actualizado_en )
```

…usada como **almacén llave-valor por empresa** (multi-tenant). El cliente tiene un helper `DB.get(clave)` / `DB.set(clave, valor)` con caché en memoria + localStorage + sync con debounce.

**En React se reemplaza así (manteniendo la MISMA tabla):**

```ts
// lib/db.ts — lectura/escritura cruda contra erp_data
export async function dbGet<T>(empresaId: string, clave: string): Promise<T | null> {
  const { data } = await supabase.from('erp_data')
    .select('datos').eq('empresa_id', empresaId).eq('clave', clave).maybeSingle();
  return (data?.datos as T) ?? null;
}
export async function dbSet(empresaId: string, clave: string, datos: unknown) {
  await supabase.from('erp_data').upsert(
    [{ empresa_id: empresaId, clave, datos, actualizado_en: new Date().toISOString() }],
    { onConflict: 'empresa_id,clave' }
  );
}
```

```ts
// lib/queries.ts — TanStack Query reemplaza el caché + debounce manual
export function useProductos() {
  const { empresaId } = useAuth();
  return useQuery({ queryKey: ['productos', empresaId],
    queryFn: () => dbGet<Producto[]>(empresaId, 'productos') });
}
export function useSetProductos() {
  const { empresaId } = useAuth(); const qc = useQueryClient();
  return useMutation({
    mutationFn: (prods: Producto[]) => dbSet(empresaId, 'productos', prods),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['productos', empresaId] }),
  });
}
```

**Realtime** (órdenes en vivo entre sesiones): suscripción a `postgres_changes` sobre `erp_data` filtrando `clave=eq.tp_orders`, que invalida la query correspondiente.

**Claves de datos actuales** (todas se reutilizan tal cual):

```
productos · stock · bodegas · proveedores · clientes · ventas · venta_log · metodos_pago
ocs · oc_log · kits · cats_db · mov_inventario · gastos · gasto_cats · tecnicos_ext
cajas_perifericas · caja_sesiones · plan_cuentas · asientos · cat_cuenta
tp_orders · tp_equipos · tp_config · tp_seg_config · tp_smtp_config · tp_email_domain
tp_terminos · tp_msg_templates · tp_cl_ingreso · tp_cl_salida · tp_custom_cats · tp_custom_subcats
cargos · user_cargo_map · ucfg_<userId>
```

> **Importante:** mantener el modelo llave-valor en esta fase. Normalizar a tablas reales (productos, ordenes, etc.) es un proyecto posterior (§10), no se mezcla con la migración de UI.

---

## 5. Orden de migración (fases)

| Fase | Qué se construye | Resultado |
|---|---|---|
| **0. Setup** | Proyecto Vite+React+TS, Supabase, Tailwind, shadcn, router, TanStack Query | App vacía conectada al Supabase real |
| **1. Cimientos** | AuthContext (login, empresaId, rol, sucursal), Shell (Sidebar+Topbar), capa `db.ts`+`queries.ts`, componentes compartidos (DataTable, Money, Modal, FormField) | Login funcionando + layout |
| **2. Taller** | Órdenes, detalle, inspección, fotos QR, equipos, traslados, settings del taller | Módulo estrella migrado |
| **3. Inventario** | Productos (stock por sucursal), bodegas, movimientos, categorías, kits, órdenes de compra (OC) | Inventario completo |
| **4. Ventas** | POS, ventas, caja (apertura/cierre), métodos de pago | Punto de venta |
| **5. Contactos** | Clientes, proveedores | — |
| **6. Contabilidad + Gastos** | Plan de cuentas, asientos, gastos | — |
| **7. Dashboard + Estadísticas** | KPIs globales y por sucursal, gráficos | — |
| **8. Configuración** | Seguimiento, SMTP, dominio (Resend), términos, mensajes, cargos, accesos | Cierra paridad |
| **9. Cutover** | Pruebas de paridad, apuntar dominio a la versión React | Producción |

> Se empieza por **Taller** porque es el módulo más usado y el que más valida que el patrón (datos + componentes + realtime) funciona end-to-end.

---

## 6. Especificación por módulo (mapeo desde el código actual)

> Para cada módulo: pantallas a recrear, claves de datos que usa, y lógica a reutilizar.

### Cimientos / Auth
- **Hoy:** `doLogin`, `_iniciarApp`, `_cargarDesdeSupabase`, `_applyRoleAccess`, `nav`, `navTaller`, sidebar.
- **Datos:** Auth de Supabase, `user_profiles`, `empresas`, `cargos`, `user_cargo_map`, `ucfg_<userId>`.
- **React:** `AuthContext` (user, empresaId, rol, branchContext) + `<ProtectedRoute>` + `Sidebar` con visibilidad por permisos de cargo.

### Taller
- **Hoy:** `renderTaller`, `tp_renderOrders`, `tp_openDetail`, `tp_saveOrder`, `tp_openInspeccionModal`, `tp_saveInspeccion`, `tp_enviarInspeccionReporte`, `tp_showQrFotos`, traslados (`_renderTrasladosContent`, `tp_derivarOrden`), settings (`tp_settingsTab`).
- **Datos:** `tp_orders`, `tp_equipos`, `tp_cl_ingreso/salida`, `tp_custom_cats/subcats`, `traslados`, `tecnicos_ext`, `tp_config`, `tp_seg_config`, `tp_terminos`, `tp_msg_templates`.
- **Lógica a reutilizar:** armado de correos de ingreso/listo/inspección (HTML), checklist, fotos por QR (página `foto-orden.html` se mantiene), realtime de órdenes.
- **Pantallas React:** Lista de órdenes (DataTable con filtros por estado), Detalle de orden, Modal nueva/editar orden, Modal inspección, Equipos, Traslados, Settings del taller.

### Inventario
- **Hoy:** `renderProductos`/`renderProdsTable`, `modalAjusteStock`, `renderBodegas`, `renderMovimientos`, `renderCategorias`, `renderKits`, `renderOC`/`renderOCTable`.
- **Datos:** `productos`, `stock`, `bodegas`, `mov_inventario`, `cats_db`, `kits`, `ocs`, `oc_log`.
- **Lógica a reutilizar:** stock por sucursal (`stock_sucursales`, `getProdStockTotal/Sucursal`), import/export Excel de productos, registro de movimientos.
- **Pantallas:** Productos (grilla con stock por sucursal), Modal ajuste de stock multi-sucursal, Bodegas, Movimientos, Categorías, Kits, Órdenes de Compra.

### Ventas
- **Hoy:** `renderVentas`/`renderVentasTable`, `_renderPOS`/`_renderPOSCart`/`_renderPOSTotales`, `renderCaja`, `_cajaAbrir`/`_cajaCerrarModal`, `renderVentasConfig`.
- **Datos:** `ventas`, `venta_log`, `metodos_pago`, `cajas_perifericas`, `caja_sesiones`.
- **Lógica a reutilizar:** cálculo de totales/IVA, rebaja de stock al vender, vínculo venta↔orden de taller, sesiones de caja.
- **Pantallas:** POS (carrito), Lista de ventas, Caja (apertura/cierre/arqueo), Config de ventas.

### Contactos
- **Hoy:** `renderClientes`/`renderClientesTable`, `renderProveedores`/`renderProvsTable`.
- **Datos:** `clientes`, `proveedores`. **Lógica:** auto-formato RUT, capitalización, import Excel.

### Contabilidad + Gastos
- **Hoy:** `renderContabilidad`/`renderContBody`, `renderGastos`/`renderGastosTable`.
- **Datos:** `plan_cuentas`, `asientos`, `cat_cuenta`, `gastos`, `gasto_cats`.

### Dashboard + Estadísticas
- **Hoy:** `renderDashboard`→`_renderDashboardGlobal`/`_renderDashboardLocal`, `renderEstadisticas`.
- **Datos:** lee de ventas, gastos, ocs, productos, tp_orders. **Reutilizar:** KPIs y agregaciones; pasar gráficos a Recharts.

### Configuración
- **Hoy:** `renderConfigGlobal` (Correo: dominio + SMTP), `tp_settingsTab` (seguimiento, checklist, mensajes, términos), `renderCargos`, `renderSysUsuarios` (accesos), `tp_domainBodyHtml`/`tp_createDomain`/`tp_checkDomain`.
- **Datos:** `tp_seg_config`, `tp_smtp_config`, `tp_email_domain`, `tp_terminos`, `tp_msg_templates`, `cargos`, `user_cargo_map`.
- **Reutilizar:** flujo de verificación de dominio (Edge Function `manage-domain`), envío de correos (`send-email`).

---

## 7. Reglas de ejecución (para el programador y para Sonnet)

1. **Un módulo por sesión/PR.** No mezclar módulos. Cada módulo entra, se prueba y se mergea solo.
2. **No tocar el esquema de la base de datos.** Solo leer/escribir `erp_data` por clave (§4).
3. **Reutilizar la lógica del archivo actual.** Antes de reescribir un cálculo, buscar la función equivalente en `index.html` y portarla 1:1 (mismos nombres de campos).
4. **Mismos nombres de campos en `datos`.** Ej: una orden mantiene `nombre, modelo, pin, repuestos, photosIngreso, stock_sucursales`, etc. (no renombrar; rompería la compatibilidad con el ERP actual y los datos existentes).
5. **TypeScript estricto.** Definir el tipo en `types/` antes de construir el módulo.
6. **Componentes compartidos primero.** DataTable, Money, Modal, FormField, Badge se hacen una vez en Fase 1 y se reutilizan.
7. **Paridad antes de avanzar.** Un módulo está "listo" cuando hace TODO lo que hace el actual (ver §9).

---

## 8. Setup inicial (Fase 0 — comandos)

```bash
npm create vite@latest erp-react -- --template react-ts
cd erp-react
npm i @supabase/supabase-js @tanstack/react-query @tanstack/react-table \
      react-router-dom react-hook-form zod xlsx recharts
# Tailwind + shadcn/ui según su documentación oficial
```

- Copiar las credenciales de Supabase (URL + anon key) desde `index.html` (`_SB_URL`, `_SB_KEY`).
- Configurar el cliente Supabase con la persistencia de sesión (igual que en el ERP actual: `persistSession`, `autoRefreshToken`, `storage: localStorage`, `detectSessionInUrl:false`).
- Las **Edge Functions** (`send-email`, `manage-domain`) y los **secrets** (`RESEND_API_KEY`) NO se tocan: ya están en Supabase y se invocan igual.

---

## 9. Definición de "listo" por módulo (checklist de paridad)

Un módulo se considera migrado cuando, comparado con el ERP actual:

- [ ] Muestra los mismos datos (lee de las mismas claves de `erp_data`).
- [ ] Crea/edita/elimina con los mismos campos y validaciones.
- [ ] Respeta rol y sucursal (super-admin global vs encargado por sucursal).
- [ ] Import/export Excel funciona (donde aplique).
- [ ] Correos/PDF/QR funcionan (donde aplique).
- [ ] Se actualiza en tiempo real donde el actual lo hace (órdenes).
- [ ] Responsive (móvil/tablet) como el actual.

---

## 10. Después de la migración (fuera de alcance ahora)

Una vez todo en React y estable, recién ahí considerar (proyecto separado):

- **Normalizar la base de datos:** pasar de `erp_data` (llave-valor) a tablas reales (`productos`, `ordenes`, `ventas`…) con relaciones e índices. Mejora consultas y reportes a escala.
- Roles/permisos a nivel base de datos (RLS por tabla).
- Reportería avanzada, multi-moneda, etc.

> No hacer esto durante la migración de UI: son dos cambios grandes y riesgosos que no se combinan.

---

## Resumen en una frase

**Se rehace la interfaz en React (Vite + TS + Supabase + shadcn/TanStack), módulo por módulo, reutilizando la misma base de datos y la misma lógica, empezando por Taller, sin apagar el ERP actual hasta tener paridad total.**
