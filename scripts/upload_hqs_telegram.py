"""
Script de Upload e Catalogação Automática de HQs para o Telegram (YOMI)
======================================================================
- Varre pastas de quadrinhos (PDF, CBZ, CBR, ZIP)
- Detecta automaticamente o Título da Obra preservando hierarquias (Ex: Aranhaverso - 2014)
- Previne DUPLICATAS por hash SHA-256 e por numeração de capítulo
- Salva o histórico de envios em 'uploaded_hqs_ledger.json' para poder pausar e continuar
- Gera lista detalhada 'hqs_acima_de_50mb.txt' para os poucos arquivos maiores que 50MB
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
OVERSIZED_REPORT_FILE = "hqs_acima_de_50mb.txt"

SUPPORTED_EXTENSIONS = {".pdf", ".cbz", ".cbr", ".zip", ".cbt"}
TELEGRAM_MAX_BYTES = 50 * 1024 * 1024  # 50 MB limite do Bot API padrão


def clean_title(s: str) -> str:
    """Higieniza o nome da obra removendo tags de scan, anos ou ruídos comuns."""
    s = re.sub(r"\[.*?\]", "", s)
    s = s.replace("_", ": ")
    s = re.sub(r"\s+", " ", s).strip()
    return s


def resolve_series_title(file_path: Path, base_dir: Path) -> str:
    """Extrai o título limpo da série preservando a hierarquia da pasta."""
    try:
        rel = file_path.parent.relative_to(base_dir)
        parts = rel.parts
    except Exception:
        parts = (file_path.parent.name,)

    # Ignora prefixos genéricos como 'MARVEL DRIVE', 'Downloads', 'HQs'
    meaningful_parts = [
        p for p in parts
        if p.lower() not in {"marvel drive", "drive", "hqs", "comics", "downloads", "download", "pdf", "pdfs"}
    ]

    if not meaningful_parts:
        return clean_title(file_path.parent.name)

    if len(meaningful_parts) == 1:
        return clean_title(meaningful_parts[0])

    main_cat = clean_title(meaningful_parts[0])
    sub_cat = clean_title(meaningful_parts[1])

    if main_cat.lower() == sub_cat.lower() or sub_cat.lower().startswith(main_cat.lower()):
        return sub_cat
    return f"{main_cat} - {sub_cat}"


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

    body = bytearray()
    body.extend(f"--{boundary}\r\n".encode("utf-8"))
    body.extend(f'Content-Disposition: form-data; name="chat_id"\r\n\r\n{CHANNEL_ID}\r\n'.encode("utf-8"))

    body.extend(f"--{boundary}\r\n".encode("utf-8"))
    body.extend(f'Content-Disposition: form-data; name="caption"\r\n\r\n{caption}\r\n'.encode("utf-8"))

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
            with urllib.request.urlopen(req, timeout=180) as response:
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

    print(f"\n✅ Catálogo YOMI atualizado com sucesso em '{CATALOG_FILE}'! ({len(catalog)} obras catalogadas)")


def main():
    print("=" * 70)
    print("   🚀 YOMI VAULT - UPLOADER AUTOMÁTICO DE HQs PARA O TELEGRAM")
    print("=" * 70)

    default_path = r"C:\Users\santi\Desktop\MARVEL DRIVE-20261111T182302Z-1-011"
    if len(sys.argv) > 1:
        root_dir = Path(sys.argv[1])
    elif Path(default_path).exists():
        print(f"\n📂 Pasta padrão detectada no Desktop: {default_path}")
        user_choice = input("Pressione ENTER para usar esta pasta ou digite outro caminho: ").strip()
        root_dir = Path(user_choice.strip("\"'")) if user_choice else Path(default_path)
    else:
        user_input = input("\n📂 Digite ou cole o caminho da pasta onde estão suas HQs: ").strip()
        root_dir = Path(user_input.strip("\"'"))

    if not root_dir.exists() or not root_dir.is_dir():
        print(f"❌ Erro: O diretório '{root_dir}' não existe.")
        return

    ledger = load_ledger()
    uploaded_hashes = ledger.setdefault("uploaded_hashes", {})
    series_map = ledger.setdefault("series", {})

    print(f"\n🔍 Escaneando diretórios a partir de: {root_dir}")

    candidates = []
    oversized_files = []

    for root, dirs, files in os.walk(root_dir):
        current_path = Path(root)
        for f in files:
            ext = Path(f).suffix.lower()
            if ext in SUPPORTED_EXTENSIONS:
                full_path = current_path / f
                candidates.append(full_path)

    print(f"📦 Total de arquivos de quadrinhos encontrados: {len(candidates)}")

    if not candidates:
        print("Nenhum arquivo de quadrinho encontrado.")
        return

    # Agrupa por série preservando hierarquia de sagas/volumes
    series_batches = {}
    for path in candidates:
        series_title = resolve_series_title(path, root_dir)
        series_batches.setdefault(series_title, []).append(path)

    print(f"📚 Obras distintas identificadas: {len(series_batches)}")

    uploaded_count = 0
    skipped_count = 0
    oversized_count = 0

    for series_name, files in sorted(series_batches.items()):
        print(f"\n📖 [Obra]: {series_name} ({len(files)} arquivos)")
        series_entry = series_map.setdefault(series_name, {"category": "HQ", "chapters": []})
        existing_chapter_numbers = {c["number"] for c in series_entry["chapters"]}

        files.sort(key=lambda p: extract_chapter_number(p.name))

        for file_path in files:
            size_bytes = file_path.stat().st_size
            if size_bytes == 0:
                print(f"   ⚠️ Pulando arquivo vazio: {file_path.name}")
                skipped_count += 1
                continue

            if size_bytes > TELEGRAM_MAX_BYTES:
                size_mb = size_bytes / (1024 * 1024)
                print(f"   ⚠️ Maior que 50MB ({size_mb:.1f} MB): {file_path.name} -> Registrado para envio manual!")
                oversized_files.append((series_name, file_path, size_mb))
                oversized_count += 1
                continue

            ch_num = extract_chapter_number(file_path.name)

            if ch_num in existing_chapter_numbers:
                print(f"   🔁 Capítulo {ch_num:g} já cadastrado para '{series_name}'. Pulando repetição ({file_path.name})...")
                skipped_count += 1
                continue

            file_hash = calculate_sha256(file_path)
            if file_hash in uploaded_hashes:
                print(f"   🔁 Conteúdo idêntico detectado (hash {file_hash[:8]}). Pulando ({file_path.name})...")
                skipped_count += 1
                continue

            safe_tag = re.sub(r"[^a-zA-Z0-9]", "", series_name)[:25]
            caption = f"#{safe_tag} | {series_name} - Cap. {ch_num:g}"

            size_mb = size_bytes / (1024 * 1024)
            print(f"   ⬆️ Enviando Cap. {ch_num:g}: {file_path.name} ({size_mb:.1f} MB)...", end="", flush=True)

            try:
                result = send_telegram_document(file_path, caption)
                doc = result.get("document", {})
                file_id = doc.get("file_id")

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

                time.sleep(1.8)

            except Exception as e:
                print(f" [ERRO: {e}]")
                time.sleep(3)

    if oversized_files:
        with open(OVERSIZED_REPORT_FILE, "w", encoding="utf-8") as f:
            f.write("# RELATÓRIO DE ARQUIVOS MAIORES QUE 50MB (Para envio manual pelo Telegram Desktop)\n\n")
            for s_name, f_path, sz in oversized_files:
                f.write(f"[{s_name}] ({sz:.1f} MB): {f_path}\n")
        print(f"\n⚠️ Foi gerado o relatório '{OVERSIZED_REPORT_FILE}' com {len(oversized_files)} arquivos que passaram de 50MB.")

    print("\n" + "=" * 70)
    print(f"🎉 Processo concluído!")
    print(f"   ⬆️ Arquivos enviados com sucesso pelo bot: {uploaded_count}")
    print(f"   🔁 Repetições e duplicatas evitadas: {skipped_count}")
    print(f"   📦 Arquivos acima de 50MB (para arrastar no app): {oversized_count}")
    print("=" * 70)

    generate_catalog_from_ledger(ledger)


if __name__ == "__main__":
    main()
