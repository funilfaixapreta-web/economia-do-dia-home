// ============================================================================
// Economia do Dia · asaas-webhook
// ----------------------------------------------------------------------------
// O ASAAS avisa aqui quando um pagamento muda. E daqui que a compra vira
// acesso sem ninguem apertar botao.
//
//   PAYMENT_CONFIRMED / PAYMENT_RECEIVED      -> libera o pedido
//   PAYMENT_REFUNDED / PAYMENT_CHARGEBACK_*   -> estorna e desliga o acesso
//   resto (CREATED, OVERDUE, DELETED...)      -> so registra
//
// Seguranca: o ASAAS manda o token cadastrado no webhook no cabecalho
// "asaas-access-token". Tem de bater com o segredo ASAAS_WEBHOOK_TOKEN.
//
// Sempre 200 depois de registrar: se responder erro, o ASAAS reenvia e, depois
// de 15 falhas seguidas, PAUSA a fila inteira. Problema de pedido fica anotado
// em asaas_eventos.resultado para conferir, nao vira erro HTTP.
// ============================================================================
import { createClient } from "jsr:@supabase/supabase-js@2";

const TOKEN = Deno.env.get("ASAAS_WEBHOOK_TOKEN") ?? "";
const METODO: Record<string, string> = {
  PIX: "pix", CREDIT_CARD: "cartao", DEBIT_CARD: "cartao", BOLETO: "boleto",
};
const LIBERA = new Set(["PAYMENT_CONFIRMED", "PAYMENT_RECEIVED"]);
const ESTORNA = new Set(["PAYMENT_REFUNDED", "PAYMENT_CHARGEBACK_REQUESTED", "PAYMENT_CHARGEBACK_DISPUTE"]);

const ok = (corpo: unknown = { ok: true }) =>
  new Response(JSON.stringify(corpo), { headers: { "Content-Type": "application/json" } });

// comparacao de tempo constante: nao entrega o token por cronometro
function igual(a: string, b: string) {
  if (!a || !b || a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("metodo", { status: 405 });
  if (!TOKEN || !igual(req.headers.get("asaas-access-token") ?? "", TOKEN)) {
    return new Response("nao autorizado", { status: 401 });
  }

  let ev: any;
  try { ev = await req.json(); } catch { return ok({ ok: false, motivo: "json" }); }
  const pag = ev?.payment ?? {};
  const evento = String(ev?.event ?? "");
  const idEvento = String(ev?.id ?? `${evento}:${pag.id ?? ""}:${pag.status ?? ""}`);

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });

  // qual pedido: externalReference e o id do pedido; se nao vier, pelo id da cobranca
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  let ped: any = null;
  if (uuid.test(String(pag.externalReference ?? ""))) {
    ({ data: ped } = await db.from("pedidos").select("*").eq("id", pag.externalReference).maybeSingle());
  }
  if (!ped && pag.id) {
    ({ data: ped } = await db.from("pedidos").select("*").eq("gateway_id", pag.id).maybeSingle());
  }

  // grava antes de agir: se ja existe, e reenvio e nao se faz nada de novo
  const { error: dup } = await db.from("asaas_eventos").insert({
    id: idEvento, evento, pagamento_id: pag.id ?? null, pedido_id: ped?.id ?? null, payload: ev,
  });
  if (dup) {
    if (dup.code === "23505") return ok({ ok: true, repetido: true });
    console.error("asaas-webhook registro", dup.message);
  }

  const anota = (resultado: string) =>
    db.from("asaas_eventos").update({ resultado }).eq("id", idEvento);

  if (!ped) {
    await anota("sem-pedido");
    return ok({ ok: true, motivo: "sem-pedido" });
  }

  try {
    if (LIBERA.has(evento)) {
      // o valor que entrou tem de fechar com o pedido. Parcelado: cada parcela
      // vale total/n, com folga de centavos de arredondamento.
      const n = Math.max(1, ped.parcelas ?? 1);
      const esperado = ped.total_centavos / n;
      const veio = Math.round(Number(pag.value ?? 0) * 100);
      if (Math.abs(veio - esperado) > n) {
        await anota(`valor-diferente: veio ${veio}, esperado ${Math.round(esperado)}`);
        return ok({ ok: true, motivo: "valor-diferente" });
      }
      const { data, error } = await db.rpc("liberar_pedido_interno", {
        p_pedido: ped.id,
        p_metodo: METODO[pag.billingType] ?? ped.metodo ?? "pix",
        p_gateway: "asaas",
        p_gateway_id: ped.gateway_id ?? pag.id,
      });
      if (error) throw error;
      await anota(data?.ok ? (data.ja_pago ? "ja-pago" : `liberado: ${data.matriculas} matricula(s)`) : `nao-liberado: ${data?.motivo}`);
      return ok();
    }

    if (ESTORNA.has(evento)) {
      const { data, error } = await db.rpc("estornar_pedido_interno", {
        p_pedido: ped.id, p_gateway_id: ped.gateway_id ?? pag.id,
      });
      if (error) throw error;
      await anota(`estornado: ${data?.matriculas_desligadas ?? 0} matricula(s) desligada(s)`);
      return ok();
    }

    await anota("registrado");
    return ok();
  } catch (e: any) {
    console.error("asaas-webhook", evento, ped.id, e?.message);
    await anota("erro: " + (e?.message ?? "desconhecido"));
    return ok({ ok: false });
  }
});
