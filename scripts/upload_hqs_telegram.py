"""
Script de Upload e Catalogação Automática de HQs para o Telegram (YOMI)
======================================================================
- Varre pastas de quadrinhos (PDF, CBZ, CBR, ZIP)
- Detecta automaticamente o Título da Obra (nome da pasta) e o Capítulo
- Previne DUPLICATAS por hash SHA-256 e por numeração de capítulo
- Salva o histórico de envios em 'uploaded_hqs_ledger.json' para poder pausar e continuar
- Gera o catálogo 'yomi_hqs_catalog.json' pronto para consumo no aplicativo YOMI!
"""

import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

# Configurações do Bot e Canal Telegram
BOT_TOKEN = "9226471608:AAGR6VQL6i7zLHLK4c2F9k69efPE6kfyGfw"
CHANNEL_ID = "-1004356625326"  # Canal: Acervo YOMI HQs
LEDGER_FILE = "uploaded_hqs_ledger.json"
CATALOG_FILE = "yomi_hqs_catalog.json"

SUPPORTED_EXTENSIONS = {".pdf", ".cbz", ".cbr", ".zip"}
TELEGRAM_MAX_BYTES = 50 * 1024 * 1024  # 50 MB limite do Bot API padrão


def clean_title(raw_name: str) -> str:
    """Higieniza o nome da obra removendo tags de scan, anos ou ruídos comuns."""
    cleaned = re.sub(r"\[.*?\]|\(.*?\)", "", raw_name)
    cleaned = re.sub(r"[-_]+", " ", cleaned)
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    return cleaned if cleaned else raw_name.strip()


def extract_chapter_number(file_name: str) -> float:
    """Extrai o número do capítulo do nome do arquivo."""
    base = Path(file_name).stem.lower()
    # Padrões comuns: 'capitulo 01', 'cap. 02.5', 'c03', 'edição 04', '#05', '06'
    match = re.search(r"(?:cap[ií]tulo|cap|edi[çc][ãa]o|ed|issue|#)\s*([0-9]+(?:[\.,][0-9]+)?)", base)
    if match:
        num_str = match.group(1).replace(",", ".")
        try:
            return float(num_str)
        except ValueError:
            pass

    # Se só tiver números no nome: ex '01.pdf'
    num_match = re.search(r"(\d+(?:\.\d+)?)", base)
    if num_match:
        try:
            return float(num_match.group(1))
        except ValueError:
            pass

    return 1.0


def calculate_sha256(file_path: Path) -> str:
    """Calcula hash rápido SHA-256 do arquivo para evitar duplicatas idênticas."""
    hasher = hashlib.sha256()
    with open(file_path, "rb") as f:
        # Lê os primeiros 2MB e os últimos 2MB para velocidade em arquivos grandes
        chunk = f.read(2 * 1024 * 1024)
        hasher.update(chunk)
        if file_path.stat().st_size > 4 * 1024 * 1024:
            f.seek(-2 * 1024 * 1024, os.SEEK_END)
            hasher.update(f.read())
    return hasher.hexdigest()


def load_ledger() -> dict:
    if os.path.exists(LEDGER_FILE):
        try:
            with open(LEDGER_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {"uploaded_hashes": {}, "series": {}}


def save_ledger(ledger: dict):
    with open(LEDGER_FILE, "w", encoding="utf-8") as f:
        json.dump(ledger, f, indent=2, ensure_ascii=False)


def send_telegram_document(file_path: Path, caption: str) -> dict:
    """Faz o upload do arquivo para o Telegram usando multipart/form-data nativo."""
    boundary = "----YomiTelegramBoundary" + hashlib.md5(str(time.time()).encode()).hexdigest()
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendDocument"

    # Constrói o corpo multipart
    body = bytearray()

    # Campo chat_id
    body.extend(f"--{boundary}\r\n".encode("utf-8"))
    body.extend(f'Content-Disposition: form-data; name="chat_id"\r\n\r\n{CHANNEL_ID}\r\n'.encode("utf-8"))

    # Campo caption
    body.extend(f"--{boundary}\r\n".encode("utf-8"))
    body.extend(f'Content-Disposition: form-data; name="caption"\r\n\r\n{caption}\r\n'.encode("utf-8"))

    # Campo document
    file_name = file_path.name
    body.extend(f"--{boundary}\r\n".encode("utf-8"))
    body.extend(
        f'Content-Disposition: form-data; name="document"; filename="{file_name}"\r\n'
        f"Content-Type: application/octet-stream\r\n\r\n".encode("utf-8")
    )

    with open(file_path, "rb") as f:
        body.extend(f.read())
    body.extend(f"\r\n--{boundary}--\r\n".encode("utf-8"))

    headers = {
        "Content-Type": f"multipart/form-data; boundary={boundary}",
        "User-Agent": "YOMI-Vault-Uploader/1.0",
    }

    req = urllib.request.Request(url, data=bytes(body), headers=headers, method="POST")

    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=120) as response:
                res_data = json.loads(response.read().decode("utf-8"))
                if res_data.get("ok"):
                    return res_data["result"]
                raise RuntimeError(f"Resposta de erro do Telegram: {res_data}")
        except urllib.error.HTTPError as e:
            if e.code == 429:
                wait_sec = 25 * (attempt + 1)
                print(f"   ⚠️ Limite de requisições do Telegram atingido. Aguardando {wait_sec}s...")
                time.sleep(wait_sec)
            else:
                err_content = e.read().decode("utf-8", errors="ignore")
                raise RuntimeError(f"HTTP {e.code}: {err_content}")
        except Exception as ex:
            if attempt < 3:
                time.sleep(5 * (attempt + 1))
            else:
                raise ex

    raise RuntimeError("Falha após 4 tentativas de upload.")


def generate_catalog_from_ledger(ledger: dict):
    """Gera o catálogo de HQs compatível com o leitor YOMI."""
    catalog = []
    for series_name, series_data in ledger.get("series", {}).items():
        chapters = series_data.get("chapters", [])
        # Ordena capítulos por número
        chapters.sort(key=lambda c: c.get("number", 0))

        catalog.append({
            "id": f"tg_{hashlib.md5(series_name.encode()).hexdigest()[:12]}",
            "title": series_name,
            "category": series_data.get("category", "HQ"),
            "chapters_count": len(chapters),
            "cover_file_id": chapters[0].get("file_id") if chapters else None,
            "chapters": chapters,
        })

    with open(CATALOG_FILE, "w", encoding="utf-8") as f:
        json.dump({"total_series": len(catalog), "items": catalog}, f, indent=2, ensure_ascii=False)

    print(f"\n✅ Catálogo YOMI atualizado com sucesso em '{CATALOG_FILE}'! ({len(catalog)} obras)")


def main():
    print("=" * 70)
    print("   🚀 YOMI VAULT - UPLOADER AUTOMÁTICO DE HQs PARA O TELEGRAM")
    print("=" * 70)

    if len(sys.argv) > 1:
        root_dir = Path(sys.argv[1])
    else:
        user_input = input("\n📂 Digite ou cole o caminho da pasta onde estão suas HQs: ").strip()
        user_input = user_input.strip("\"'")
        root_dir = Path(user_input)

    if not root_dir.exists() or not root_dir.is_dir():
        print(f"❌ Erro: O diretório '{root_dir}' não existe.")
        return

    ledger = load_ledger()
    uploaded_hashes = ledger.setdefault("uploaded_hashes", {})
    series_map = ledger.setdefault("series", {})

    print(f"\n🔍 Escaneando diretórios a partir de: {root_dir}")

    # Coleta todos os arquivos válidos
    candidates = []
    for root, dirs, files in os.walk(root_dir):
        current_path = Path(root)
        for f in files:
            ext = Path(f).suffix.lower()
            if ext in SUPPORTED_EXTENSIONS:
                full_path = current_path / f
                candidates.append(full_path)

    print(f"📦 Total de arquivos de quadrinhos encontrados: {len(candidates)}")

    if not candidates:
        print("Nenhum arquivo .pdf, .cbz ou .zip encontrado.")
        return

    # Agrupa por série baseada no nome da pasta
    series_batches = {}
    for path in candidates:
        # Se os arquivos estiverem em uma subpasta (ex: Marvel / X-Men / Cap 01.pdf)
        # O nome da história é a pasta pai imediata
        parent_name = path.parent.name
        # Se a pasta pai for genérica (ex: 'PDFs' ou 'Downloads'), usa o avô
        if parent_name.lower() in {"pdf", "pdfs", "download", "downloads", "hqs", "comics"} and path.parent != root_dir:
            series_title = clean_title(path.parent.parent.name)
        else:
            series_title = clean_title(parent_name)

        series_batches.setdefault(series_title, []).append(path)

    print(f"📚 Obras distintas identificadas: {len(series_batches)}")

    uploaded_count = 0
    skipped_count = 0

    for series_name, files in series_batches.items():
        print(f"\n📖 [Obra]: {series_name} ({len(files)} arquivos)")
        series_entry = series_map.setdefault(series_name, {"category": "HQ", "chapters": []})
        existing_chapter_numbers = {c["number"] for c in series_entry["chapters"]}

        # Ordena os arquivos pelo número do capítulo
        files.sort(key=lambda p: extract_chapter_number(p.name))

        for file_path in files:
            size_bytes = file_path.stat().st_size
            if size_bytes == 0:
                print(f"   ⚠️ Pulando arquivo vazio: {file_path.name}")
                skipped_count += 1
                continue

            if size_bytes > TELEGRAM_MAX_BYTES:
                print(f"   ⚠️ Arquivo maior que 50MB (limite do Bot Telegram): {file_path.name} ({size_bytes / (1024*1024):.1f} MB)")
                skipped_count += 1
                continue

            ch_num = extract_chapter_number(file_path.name)

            # Prevenção 1: Checa se o capítulo já foi cadastrado para essa obra
            if ch_num in existing_chapter_numbers:
                print(f"   🔁 Capítulo {ch_num:g} já existe para '{series_name}'. Pulando repetição ({file_path.name})...")
                skipped_count += 1
                continue

            # Prevenção 2: Checa se o arquivo exato (por hash) já foi enviado
            file_hash = calculate_sha256(file_path)
            if file_hash in uploaded_hashes:
                print(f"   🔁 Conteúdo idêntico detectado (hash {file_hash[:8]}). Pulando ({file_path.name})...")
                skipped_count += 1
                continue

            # Prepara legenda padronizada
            caption = f"#{re.sub(r'[^a-zA-Z0-9]', '', series_name)} | {series_name} - Cap. {ch_num:g}"

            print(f"   ⬆️ Enviando Cap. {ch_num:g}: {file_path.name} ({size_bytes / (1024*1024):.1f} MB)...", end="", flush=True)

            try:
                result = send_telegram_document(file_path, caption)
                doc = result.get("document", {})
                file_id = doc.get("file_id")

                # Registra no ledger
                series_entry["chapters"].append({
                    "number": ch_num,
                    "title": f"Capítulo {ch_num:g}",
                    "file_name": file_path.name,
                    "file_id": file_id,
                    "message_id": result.get("message_id"),
                    "file_size": size_bytes,
                })
                existing_chapter_numbers.add(ch_num)
                uploaded_hashes[file_hash] = {
                    "series": series_name,
                    "chapter": ch_num,
                    "file_id": file_id,
                }
                save_ledger(ledger)
                uploaded_count += 1
                print(" [OK]")

                # Intervalo suave para respeitar os limites do Telegram
                time.sleep(1.8)

            except Exception as e:
                print(f" [ERRO: {e}]")
                time.sleep(3)

    print("\n" + "=" * 70)
    print(f"🎉 Processo concluído!")
    print(f"   ⬆️ Arquivos enviados com sucesso: {uploaded_count}")
    print(f"   🔁 Repetições e duplicatas evitadas: {skipped_count}")
    print("=" * 70)

    # Gera o catálogo final
    generate_catalog_from_ledger(ledger)


if __name__ == "__main__":
    main()
