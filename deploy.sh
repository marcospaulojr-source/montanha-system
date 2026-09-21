#!/usr/bin/env bash
# Deploy do Montanha Studio pra produção (Locaweb, via FTP).
#
# Produção: https://montanhafilmes.com.br/sistema/
# Credencial (nunca passe a senha na linha de comando), uma das duas formas:
#   a) ~/.netrc (recomendado, fica permanente):
#        machine ftp.montanhafilmes.com.br login montanhafilmes2 password <senha>
#        chmod 600 ~/.netrc
#   b) variável de ambiente só na hora:  FTP_PASS='<senha>' ./deploy.sh
#
# Uso:
#   ./deploy.sh          # sobe só o index.html (caso comum)
#   ./deploy.sh --all    # sobe também manifest.json, sw.js e ícones
set -euo pipefail
cd "$(dirname "$0")"

HOST='ftp.montanhafilmes.com.br'
BASE="ftp://${HOST}/public_html/sistema"
PROD_URL='https://montanhafilmes.com.br/sistema/'

FTP_USER='montanhafilmes2'
if [ -n "${FTP_PASS:-}" ]; then
  AUTH=(-u "${FTP_USER}:${FTP_PASS}")
elif [ -f ~/.netrc ] && grep -q "$HOST" ~/.netrc; then
  AUTH=(--netrc)
else
  echo "✗ Sem credencial: crie o ~/.netrc ou passe FTP_PASS (veja o cabeçalho deste script)"; exit 1
fi

# 1) Não sobe index.html com erro de sintaxe no JS inline
node -e '
const h=require("fs").readFileSync("index.html","utf8");
const re=/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g;let m,n=0;
while((m=re.exec(h))){n++;new Function(m[1])}
console.log("✓ sintaxe JS OK ("+n+" bloco(s))")'

# 2) Upload
files=(index.html)
[ "${1:-}" = "--all" ] && files+=(manifest.json sw.js icon-192.png icon-512.png)
for f in "${files[@]}"; do
  printf -- "→ %-14s " "$f"
  curl -sS "${AUTH[@]}" --ssl --connect-timeout 20 --ftp-create-dirs -T "$f" "$BASE/$f" -w "ok (%{size_upload} bytes)\n"
done

# 3) Confere que produção ficou igual ao local
local_sum=$(shasum -a 256 index.html | cut -d' ' -f1)
prod_sum=$(curl -sS -m 20 -H 'Cache-Control: no-cache' "$PROD_URL" | shasum -a 256 | cut -d' ' -f1)
if [ "$local_sum" = "$prod_sum" ]; then
  echo "✓ Produção atualizada e idêntica ao local: $PROD_URL"
else
  echo "⚠️ Upload feito, mas o conteúdo em $PROD_URL ainda difere do local (cache do servidor? tente de novo em alguns segundos)"; exit 2
fi
