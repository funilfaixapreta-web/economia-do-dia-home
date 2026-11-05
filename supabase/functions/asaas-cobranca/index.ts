// ============================================================================
// Economia do Dia · asaas-cobranca
// ----------------------------------------------------------------------------
// O checkout ja criou o pedido (criar_pedido, preco da tabela). Aqui o pedido
// vira cobranca no ASAAS e a tela recebe o que mostrar:
//
//   pix     -> QR code + copia e cola (acesso cai sozinho pelo webhook)
//   cartao  -> link da pagina segura do ASAAS, em 1 a 12 parcelas
//   boleto  -> link do boleto + linha digitavel
//
// Entrada: POST { pedido, metodo, parcelas? } com o token do aluno.
// O valor NUNCA vem do navegador: sai de pedidos.total_centavos.
//
// Segredos (Edge Functions > Secrets):
//   ASAAS_API_KEY   chave da conta. "$aact_hmlg_..." = sandbox, senao producao.
// Sem a chave, devolve motivo "gateway-desligado" e o checkout segue no modo
// antigo (pedido aguardando, admin confirma na mao).
// ============================================================================
import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function resposta(corpo: unknown, status = 200) {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

const CHAVE = Deno.env.get("ASAAS_API_KEY") ?? "";
const BASE = CHAVE.startsWith("$aact_hmlg_")
  ? "https://api-sandbox.asaas.com/v3"
  : "https://api.asaas.com/v3";

async function asaas(caminho: string, metodo = "GET", corpo?: unknown) {
  const r = await fetch(BASE + caminho, {
    method: metodo,
    headers: {
      "access_token": CHAVE,
      "Content-Type": "application/json",
      "User-Agent": "EconomiaDoDia/1.0",
    },
    body: corpo ? JSON.stringify(corpo) : undefined,
  });
  const texto = await r.text();
  let dado: any = null;
  try { dado = texto ? JSON.parse(texto) : null; } catch { dado = { bruto: texto }; }
  if (!r.ok) {
    const msg = dado?.errors?.map((e: any) => e.description).join(" · ") || `ASAAS ${r.status}`;
    const erro: any = new Error(msg);
    erro.status = r.status;
    throw erro;
  }
  return dado;
}

// data de hoje no fuso de Brasilia + n dias, no formato que o ASAAS pede
function diaMais(n: number) {
  const hoje = new Date(new Date().toLocaleString("en-US", { timeZone: "America/Sao_Paulo" }));
  hoje.setDate(hoje.getDate() + n);
  const p = (x: number) => String(x).padStart(2, "0");
  return `${hoje.getFullYear()}-${p(hoje.getMonth() + 1)}-${p(hoje.getDate())}`;
}

const TIPO: Record<string, string> = { pix: "PIX", cartao: "CREDIT_CARD", boleto: "BOLETO" };
const PRAZO: Record<string, number> = { pix: 1, cartao: 1, boleto: 3 };

// o que a tela mostra, a partir do pagamento criado (ou ja existente)
async function detalhes(pag: any, metodo: string) {
  const out: any = { cobranca_url: pag.invoiceUrl ?? null, vence_em: pag.dueDate ?? null };
  if (metodo === "pix") {
    try {
      const qr = await asaas(`/payments/${pag.id}/pixQrCode`);
      out.pix_qr = qr.encodedImage ?? null;
      out.pix_copia_cola = qr.payload ?? null;
    } catch (_) {
      // conta sem chave Pix: o link da fatura ainda deixa pagar
    }
  }
  if (metodo === "boleto") {
    out.boleto_url = pag.bankSlipUrl ?? null;
    try {
      const lin = await asaas(`/payments/${pag.id}/identificationField`);
      out.boleto_linha = lin.identificationField ?? null;
    } catch (_) { /* boleto ainda registrando: o link basta */ }
  }
  return out;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return resposta("ok");
  if (req.method !== "POST") return resposta({ ok: false, motivo: "metodo" }, 405);
  if (!CHAVE) return resposta({ ok: false, motivo: "gateway-desligado" });

  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const url = Deno.env.get("SUPABASE_URL")!;
  const servico = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });

  const { data: quem, error: errQuem } = await servico.auth.getUser(token);
  if (errQuem || !quem?.user) return resposta({ ok: false, motivo: "precisa-entrar" }, 401);

  let entrada: any = {};
  try { entrada = await req.json(); } catch { /* corpo vazio */ }
  const { data: ped } = await servico.from("pedidos").select("*").eq("id", entrada.pedido).maybeSingle();
  if (!ped || ped.aluno_id !== quem.user.id) {
    return resposta({ ok: false, motivo: "pedido-nao-encontrado" }, 404);
  }
  if (ped.status === "pago") {
    return resposta({ ok: true, status: "pago", numero: ped.numero, total_centavos: ped.total_centavos });
  }

  // sem metodo = "retoma a cobranca que ja existe" (a pessoa recarregou a pagina)
  const retomar = !entrada.metodo && ped.gateway === "asaas" && ped.gateway_id;
  const metodo = String(retomar ? ped.metodo : (entrada.metodo ?? ""));
  if (!TIPO[metodo]) return resposta({ ok: false, motivo: "metodo-invalido" }, 400);
  const parcelas = metodo !== "cartao" ? 1
    : retomar ? (ped.parcelas ?? 1)
    : Math.min(12, Math.max(1, parseInt(entrada.parcelas ?? "1", 10) || 1));
  const base = { numero: ped.numero, total_centavos: ped.total_centavos };
  if (ped.status !== "aguardando") return resposta({ ok: false, motivo: "pedido-" + ped.status }, 409);
  if (!ped.total_centavos || ped.total_centavos < 500) {
    return resposta({ ok: false, motivo: "valor-minimo" }, 400);
  }

  try {
    // ja existe cobranca deste pedido no mesmo formato? devolve a mesma
    if (ped.gateway === "asaas" && ped.gateway_id) {
      let atual: any = null;
      try { atual = await asaas(`/payments/${ped.gateway_id}`); } catch (_) { atual = null; }
      const mesma = atual && !atual.deleted && atual.status === "PENDING" &&
        ped.metodo === metodo && (ped.parcelas ?? 1) === parcelas;
      if (mesma) {
        return resposta({ ok: true, ...base, metodo, parcelas, ...(await detalhes(atual, metodo)) });
      }
      // trocou de forma de pagamento: a cobranca velha sai para nao pagar duas vezes
      if (atual && !atual.deleted && atual.status === "PENDING") {
        if (atual.installment) await asaas(`/installments/${atual.installment}`, "DELETE");
        else await asaas(`/payments/${atual.id}`, "DELETE");
      }
    }

    // cliente no ASAAS: um por aluno
    const doc = String(ped.documento ?? "").replace(/\D/g, "");
    if (doc.length !== 11 && doc.length !== 14) {
      return resposta({ ok: false, motivo: "cpf" }, 400);
    }
    const { data: aluno } = await servico.from("alunos")
      .select("id, nome, email, telefone, asaas_cliente_id").eq("id", ped.aluno_id).maybeSingle();
    let cliente = aluno?.asaas_cliente_id ?? null;
    if (!cliente) {
      const achados = await asaas(`/customers?cpfCnpj=${doc}&limit=1`);
      cliente = achados?.data?.[0]?.id ?? null;
    }
    if (!cliente) {
      const fone = String(ped.telefone ?? aluno?.telefone ?? "").replace(/\D/g, "").replace(/^55(?=\d{10,11}$)/, "");
      const novo = await asaas("/customers", "POST", {
        name: ped.nome || aluno?.nome || ped.email,
        cpfCnpj: doc,
        email: ped.email || aluno?.email,
        mobilePhone: fone || undefined,
        externalReference: ped.aluno_id,
      });
      cliente = novo.id;
    }
    if (aluno && aluno.asaas_cliente_id !== cliente) {
      await servico.from("alunos").update({ asaas_cliente_id: cliente }).eq("id", aluno.id);
    }

    const { data: itens } = await servico.from("pedido_itens").select("nome, quantidade").eq("pedido_id", ped.id);
    const descricao = ("Economia do Dia · Pedido nº " + ped.numero + " · " +
      (itens ?? []).map((i: any) => i.nome + (i.quantidade > 1 ? " x" + i.quantidade : "")).join(", ")).slice(0, 500);

    const valor = ped.total_centavos / 100;
    const corpo: any = {
      customer: cliente,
      billingType: TIPO[metodo],
      dueDate: diaMais(PRAZO[metodo]),
      description: descricao,
      externalReference: ped.id,
    };
    if (parcelas > 1) {
      corpo.installmentCount = parcelas;
      corpo.totalValue = valor;
    } else {
      corpo.value = valor;
    }
    const pag = await asaas("/payments", "POST", corpo);

    const extra = await detalhes(pag, metodo);
    await servico.from("pedidos").update({
      gateway: "asaas",
      gateway_id: pag.id,
      metodo,
      parcelas,
      cobranca_url: extra.boleto_url ?? extra.cobranca_url ?? null,
      pix_copia_cola: extra.pix_copia_cola ?? null,
      boleto_linha: extra.boleto_linha ?? null,
      vence_em: pag.dueDate ?? null,
    }).eq("id", ped.id);

    return resposta({ ok: true, ...base, metodo, parcelas, ...extra });
  } catch (e: any) {
    console.error("asaas-cobranca", ped.id, e?.status, e?.message);
    return resposta({ ok: false, motivo: "asaas", detalhe: e?.message ?? "erro" }, 502);
  }
});
