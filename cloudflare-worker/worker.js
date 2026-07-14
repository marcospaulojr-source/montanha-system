// Cloudflare Worker: recebe uma foto/print de extrato bancário e usa a API
// de visão da Anthropic (Claude) para extrair os lançamentos (entradas/saídas).
// A chave da Anthropic fica só aqui como secret do Worker (ANTHROPIC_API_KEY),
// nunca no index.html do app.

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function extractPrompt() {
  return `Você recebeu a imagem de um extrato bancário (print de tela ou foto).
Extraia todos os lançamentos (transações) visíveis e devolva SOMENTE um JSON válido,
sem markdown, sem texto antes ou depois, no formato:

{"lancamentos":[{"data":"YYYY-MM-DD","descricao":"texto curto","valor":123.45,"tipo":"entrada"}]}

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

    const { image, mediaType } = body || {};
    if (!image || typeof image !== "string") {
      return json({ error: "Envie 'image' (base64, sem o prefixo data:...)" }, 400);
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
          messages: [
            {
              role: "user",
              content: [
                { type: "image", source: { type: "base64", media_type: mediaType || "image/png", data: image } },
                { type: "text", text: extractPrompt() },
              ],
            },
          ],
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
    const text = data?.content?.[0]?.text ?? "";
    const match = text.match(/\{[\s\S]*\}/);
    if (!match) {
      return json({ error: "Não consegui interpretar a resposta da IA", raw: text }, 502);
    }

    let parsed;
    try {
      parsed = JSON.parse(match[0]);
    } catch {
      return json({ error: "JSON inválido devolvido pela IA", raw: text }, 502);
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
