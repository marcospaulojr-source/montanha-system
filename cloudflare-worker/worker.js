// Cloudflare Worker: recebe uma foto/print de extrato bancário OU um texto
// (transcrição de fala) descrevendo um lançamento, e usa a API da Anthropic
// para extrair os lançamentos (entradas/saídas) em JSON estruturado.
// A chave da Anthropic fica só aqui como secret do Worker (ANTHROPIC_API_KEY),
// nunca no index.html do app.

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const RESPONSE_FORMAT = `{"lancamentos":[{"data":"YYYY-MM-DD","descricao":"texto curto","valor":123.45,"tipo":"entrada"}]}`;

function imagePrompt() {
  return `Você recebeu a imagem de um extrato bancário (print de tela ou foto).
Extraia todos os lançamentos (transações) visíveis e devolva SOMENTE um JSON válido,
sem markdown, sem texto antes ou depois, no formato:

${RESPONSE_FORMAT}

Regras:
- "tipo" é "entrada" para dinheiro que entrou (crédito, recebimento, PIX recebido, depósito)
  e "saida" para dinheiro que saiu (débito, pagamento, PIX enviado, saque, tarifa).
- "valor" é sempre positivo (o tipo já indica a direção).
- "data" no formato YYYY-MM-DD. Se o ano não aparecer no extrato, use o ano atual (${new Date().getFullYear()}).
- Ignore saldo, cabeçalhos, totais e linhas que não sejam lançamentos individuais.
- Se não conseguir ler algum campo com confiança, ainda assim inclua a linha com sua melhor
  estimativa — a pessoa vai revisar tudo antes de confirmar.
- Se a imagem não for um extrato bancário, devolva {"lancamentos":[]}.`;
}

function textPrompt(spokenText, hojeISO, contas) {
  const contasList = Array.isArray(contas) && contas.length ? contas.join(", ") : null;
  return `Você recebeu a transcrição de uma pessoa falando em voz alta sobre um ou mais
lançamentos financeiros que ela quer registrar. Hoje é ${hojeISO}.

Transcrição: "${spokenText}"

Extraia o(s) lançamento(s) descrito(s) e devolva SOMENTE um JSON válido, sem markdown,
sem texto antes ou depois, no formato:

{"lancamentos":[{"data":"YYYY-MM-DD","descricao":"texto curto","valor":123.45,"tipo":"entrada","banco":"nome exato da conta ou vazio"}]}

Regras:
- "tipo" é "entrada" para dinheiro que entrou/recebeu e "saida" para dinheiro que saiu/pagou/gastou.
- "valor" é sempre positivo (o tipo já indica a direção). Converta valores falados por extenso
  ("quinhentos reais", "cinquenta conto") para número (500, 50).
- "data" no formato YYYY-MM-DD. Resolva expressões relativas usando hoje=${hojeISO}: "hoje" = ${hojeISO},
  "ontem" = dia anterior, "dia 20" ou "20" = dia 20 do mês corrente (ou anterior se ainda não chegou
  esse dia neste mês e fizer mais sentido), etc. Se não houver nenhuma menção de data, use ${hojeISO}.
- "descricao" deve ser um resumo curto e claro (ex: "Pix recebido - cliente Ana", "Pagamento freelancer").
  NUNCA inclua o nome do banco/conta dentro de "descricao" — o nome do banco/conta vai SEMPRE
  separado, no campo "banco".
- O campo "banco" é OBRIGATÓRIO em todo item da lista (nunca omita esse campo).
${contasList ? `  Se a pessoa mencionar uma conta (ou algo parecido/abreviado com uma delas), preencha "banco" com
  o nome EXATO de uma destas, copiado sem alterar nada: ${contasList}.
  Se a pessoa não mencionar nenhuma conta ou não der pra saber qual, preencha "banco" com string vazia "".` : `  Não há contas cadastradas ainda, então preencha "banco" sempre com string vazia "".`}
- Se a transcrição tiver mais de um lançamento (ex: "recebi 500 do pix e paguei 100 de uber"), devolva
  cada um como um item separado na lista.
- Se não conseguir identificar nenhum lançamento com sentido financeiro na transcrição, devolva
  {"lancamentos":[]}.`;
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response("ok", { headers: CORS_HEADERS });
    }
    if (request.method !== "POST") {
      return json({ error: "Método não permitido" }, 405);
    }

    const apiKey = env.ANTHROPIC_API_KEY;
    if (!apiKey) {
      return json({ error: "ANTHROPIC_API_KEY não configurada no Worker" }, 500);
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: "Corpo da requisição inválido (esperado JSON)" }, 400);
    }

    const { image, mediaType, text, hoje, contas } = body || {};

    let messageContent;
    if (image && typeof image === "string") {
      messageContent = [
        { type: "image", source: { type: "base64", media_type: mediaType || "image/png", data: image } },
        { type: "text", text: imagePrompt() },
      ];
    } else if (text && typeof text === "string" && text.trim()) {
      const hojeISO = typeof hoje === "string" && hoje ? hoje : new Date().toISOString().slice(0, 10);
      messageContent = [{ type: "text", text: textPrompt(text.trim(), hojeISO, contas) }];
    } else {
      return json({ error: "Envie 'image' (base64) ou 'text' (transcrição)" }, 400);
    }

    let anthropicRes;
    try {
      anthropicRes = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-api-key": apiKey,
          "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify({
          model: "claude-sonnet-4-5",
          max_tokens: 4096,
          messages: [{ role: "user", content: messageContent }],
        }),
      });
    } catch (e) {
      return json({ error: "Falha de rede ao chamar a Anthropic", detail: String(e) }, 502);
    }

    if (!anthropicRes.ok) {
      const errText = await anthropicRes.text();
      return json({ error: "Falha ao chamar a Anthropic", detail: errText }, 502);
    }

    const data = await anthropicRes.json();
    const responseText = data?.content?.[0]?.text ?? "";
    const match = responseText.match(/\{[\s\S]*\}/);
    if (!match) {
      return json({ error: "Não consegui interpretar a resposta da IA", raw: responseText }, 502);
    }

    let parsed;
    try {
      parsed = JSON.parse(match[0]);
    } catch {
      return json({ error: "JSON inválido devolvido pela IA", raw: responseText }, 502);
    }

    return json({ lancamentos: parsed.lancamentos || [] });
  },
};

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}
