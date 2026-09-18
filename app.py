import os
import re
import json
import time
from flask import Flask, render_template, request, jsonify
import psycopg2
import psycopg2.extras

app = Flask(__name__)
WORKSPACE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_FILE = os.path.join(WORKSPACE_DIR, 'config.json')

def load_db_config():
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception:
            pass
    return {
        "host": "localhost",
        "port": 5432,
        "dbname": "autosystem",
        "user": "postgres",
        "password": ""
    }

def save_db_config(cfg):
    try:
        with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
            json.dump(cfg, f, indent=2)
        return True
    except Exception as e:
        print(f"Erro ao salvar config: {e}")
        return False

def get_db_connection(cfg_override=None):
    cfg = cfg_override or load_db_config()
    conn = psycopg2.connect(
        host=cfg.get("host", "localhost"),
        port=int(cfg.get("port", 5432)),
        dbname=cfg.get("dbname", "autosystem"),
        user=cfg.get("user", "postgres"),
        password=cfg.get("password", ""),
        client_encoding='UTF8',
        connect_timeout=5
    )
    conn.set_client_encoding('UTF8')
    return conn


@app.route('/')
def index():
    return render_template('index.html')

@app.route('/resultado')
def resultado():
    return render_template('resultado.html')


@app.route('/api/config', methods=['GET', 'POST'])
def handle_config():
    if request.method == 'POST':
        data = request.json or {}
        # Não escreve no disco do servidor para isolar as credenciais entre diferentes usuários
        return jsonify({"success": True, "config": data})
    else:
        cfg = load_db_config()
        return jsonify(cfg)

@app.route('/api/test-db', methods=['POST'])
def test_db():
    cfg = request.json or load_db_config()
    try:
        conn = get_db_connection(cfg)
        cur = conn.cursor()
        cur.execute("SELECT version();")
        version = cur.fetchone()[0]
        cur.close()
        conn.close()
        return jsonify({"success": True, "message": "Conexão estabelecida com sucesso!", "version": version})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)})

@app.route('/api/empresas', methods=['POST', 'GET'])
def get_empresas():
    cfg = request.json or load_db_config()
    try:
        conn = get_db_connection(cfg)
        cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)
        cur.execute("SELECT grid, codigo, nome FROM empresa ORDER BY codigo, grid;")
        rows = cur.fetchall()
        empresas = [{"grid": r["grid"], "codigo": r["codigo"], "nome": r["nome"]} for r in rows]
        cur.close()
        conn.close()
        return jsonify({"success": True, "empresas": empresas})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)})


@app.route('/api/files', methods=['GET'])
def list_files():
    files_list = []
    allowed_exts = ('.sql', '.txt', '.xml')
    for root, dirs, files in os.walk(WORKSPACE_DIR):
        # Ignorar diretórios ocultos ou virtuais
        dirs[:] = [d for d in dirs if not d.startswith('.') and d not in ('templates', 'static', 'Doc', '__pycache__')]
        for file in files:
            if file.endswith(allowed_exts) and not file.startswith('.'):
                rel_path = os.path.relpath(os.path.join(root, file), WORKSPACE_DIR)
                files_list.append({
                    "name": file,
                    "path": rel_path,
                    "ext": os.path.splitext(file)[1].lower()
                })
    files_list.sort(key=lambda x: x['name'].lower())
    return jsonify(files_list)

@app.route('/api/file-content', methods=['POST'])
def file_content():
    data = request.json or {}
    rel_path = data.get('path', '')
    if not rel_path:
        return jsonify({"error": "Caminho de arquivo não fornecido."}), 400
        
    full_path = os.path.abspath(os.path.join(WORKSPACE_DIR, rel_path))
    
    if not os.path.normcase(full_path).startswith(os.path.normcase(WORKSPACE_DIR)) or not os.path.exists(full_path):
        return jsonify({"error": "Arquivo não encontrado ou acesso inválido."}), 404
        
    try:
        with open(full_path, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
        return jsonify({"path": rel_path, "content": content})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


def parse_sql_file_sections(text):
    """
    Separa o texto do arquivo em seções contendo título, descrição explicativa e código SQL completo.
    """
    pattern = r'(?is)((?:WITH\b[\s\S]*?)?SELECT\b[\s\S]*?;|INSERT\b[\s\S]*?;|UPDATE\b[\s\S]*?;|DELETE\b[\s\S]*?;)'
    matches = list(re.finditer(pattern, text))
    sections = []
    
    last_end = 0
    for idx, m in enumerate(matches):
        sql_code = m.group(1).strip()
        preceding_text = text[last_end:m.start()].strip()
        last_end = m.end()
        
        if len(sql_code) < 15:
            continue

        # Limpar marcação markdown 'sql' se houver
        if sql_code.lower().startswith('sql\n') or sql_code.lower().startswith('sql\r\n'):
            sql_code = sql_code[3:].strip()
            
        title = f"Consulta SQL #{len(sections) + 1}"
        desc_lines = []
        
        for line in preceding_text.split('\n'):
            line_str = line.strip()
            if not line_str or line_str.startswith('```') or line_str.lower() == 'sql':
                continue
            if any(emoji in line_str for emoji in ['🟢', '🟣', '📌', '🔑', '🔹']) or line_str.startswith('#') or line_str.startswith('--'):
                clean_title = re.sub(r'^[🟢🟣📌🔑🔹#\-\s]+', '', line_str).strip()
                if clean_title and len(clean_title) > 3:
                    title = clean_title
            else:
                desc_lines.append(line_str)
                
        description = '\n'.join(desc_lines).strip()
        
        sections.append({
            'index': len(sections) + 1,
            'title': title,
            'description': description,
            'sql': sql_code
        })
        
    return sections


@app.route('/api/parse-sections', methods=['POST'])
def parse_sections_route():
    data = request.json or {}
    text = data.get('content', '')
    sections = parse_sql_file_sections(text)
    return jsonify({"sections": sections})

def extract_executable_sql(raw_sql):
    """
    Remove ou comenta textos explicativos em português antes, no meio ou depois das consultas SQL,
    garantindo que o PostgreSQL receba apenas comandos SQL válidos e comentários iniciados por '--'.
    """
    lines = raw_sql.split('\n')
    sanitized_lines = []
    in_sql = False

    for line in lines:
        stripped = line.strip()
        if not stripped:
            sanitized_lines.append(line)
            continue

        # Se já for comentário SQL (-- ou /*), manter
        if stripped.startswith('--') or stripped.startswith('/*') or stripped.startswith('*'):
            sanitized_lines.append(line)
            continue

        # Se a linha contiver emojis/marcadores de cabeçalho explicativo, força virar comentário
        if any(char in stripped[:5] for char in ['🟢', '🟣', '📌', '🔑', '🔹', '#']):
            in_sql = False
            sanitized_lines.append('-- ' + line)
            continue

        clean_line = re.sub(r'^[^\w\s]+', '', stripped).strip()
        first_word = re.split(r'[\s\(\,]', clean_line)[0].upper() if clean_line else ''

        # Início de comando SQL
        if first_word in ('WITH', 'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'CREATE', 'DROP', 'ALTER'):
            in_sql = True
            sanitized_lines.append(line)
        elif in_sql:
            sanitized_lines.append(line)
            if ';' in line:
                in_sql = False
        else:
            # Linha de texto comum fora de bloco SQL -> comentar automaticamente
            sanitized_lines.append('-- ' + line)

    return '\n'.join(sanitized_lines)


def parse_parameters(sql_text):
    """
    Encontra todas as variáveis do tipo $nome ou :nome na query SQL.
    Ignora a sintaxe de cast nativo do PostgreSQL (ex: ::text, ::int8, ::date).
    """
    pattern = r'(?<!:)(?:\$|:)([a-zA-Z_][a-zA-Z0-9_]*)'
    matches = re.findall(pattern, sql_text)
    seen = set()
    params = []
    pg_types = {'text', 'int', 'int4', 'int8', 'integer', 'bigint', 'varchar', 'char', 'date', 'timestamp', 'numeric', 'boolean', 'float', 'double'}
    for m in matches:
        if m not in seen and not m.isdigit() and m.lower() not in pg_types:
            seen.add(m)
            params.append(m)
    return params

@app.route('/api/parse-params', methods=['POST'])
def parse_params_route():
    data = request.json or {}
    sql_text = data.get('sql', '')
    params = parse_parameters(sql_text)
    return jsonify({"params": params})

@app.route('/api/execute-sql', methods=['POST'])
def execute_sql():
    data = request.json or {}
    raw_sql = data.get('sql', '').strip()
    param_values = data.get('params', {})
    cfg = data.get('config', None)
    
    if not raw_sql:
        return jsonify({"success": False, "error": "Nenhum código SQL fornecido para execução."})

    # Isolar apenas a instrução SQL executável eliminando textos explicativos em volta
    clean_sql = extract_executable_sql(raw_sql)

    # Detectar todas as variáveis presentes na query SQL e unir com os parâmetros passados
    detected_params = parse_parameters(clean_sql)
    all_param_keys = set(detected_params) | set(param_values.keys())
    sorted_param_keys = sorted(all_param_keys, key=len, reverse=True)
    
    processed_sql = clean_sql
    substituted_params = {}
    
    for key in sorted_param_keys:
        # Se for um tipo nativo do PG, não substituir
        if key.lower() in {'text', 'int', 'int4', 'int8', 'integer', 'bigint', 'varchar', 'char', 'date', 'timestamp', 'numeric', 'boolean', 'float', 'double'}:
            continue

        val = str(param_values[key]).strip() if param_values.get(key) is not None and str(param_values[key]).strip() != '' else ''
        if not val:
            if 'empresa' in key.lower():
                val = '14572'
            elif 'ini' in key.lower():
                val = '2026-07-01'
            elif 'fim' in key.lower():
                val = '2026-07-31'
            else:
                val = '1'

        # Padrões possíveis: $key ou :key (ignorando ::key)
        # Verificar se o valor parece ser numérico ou data/string
        if val.isdigit() or (val.replace('.', '', 1).isdigit() and val.count('.') == 1):
            formatted_val = val
        elif val.upper() in ('TRUE', 'FALSE', 'NULL'):
            formatted_val = val.upper()
        else:
            # Tratar como string/data entre aspas simples escapadas
            escaped_val = val.replace("'", "''")
            formatted_val = f"'{escaped_val}'"
            
        pattern = r'(?<!:)(?:\$|:)' + re.escape(key) + r'\b'
        processed_sql = re.sub(pattern, formatted_val, processed_sql)
        substituted_params[key] = formatted_val



    start_time = time.time()
    
    try:
        conn = get_db_connection(cfg)
        cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)
        
        # Executa a instrução SQL
        cur.execute(processed_sql)
        
        rows = []
        columns = []
        
        if cur.description:
            columns = [desc[0] for desc in cur.description]
            raw_rows = cur.fetchall()
            for r in raw_rows:
                row_dict = {}
                for col in columns:
                    val = r[col]
                    # Formatar tipos especiais como Decimal/Date para JSON
                    if hasattr(val, 'isoformat'):
                        row_dict[col] = val.isoformat()
                    elif isinstance(val, (int, float)):
                        row_dict[col] = val
                    elif val is None:
                        row_dict[col] = None
                    else:
                        row_dict[col] = str(val)
                rows.append(row_dict)
                
        elapsed_time = round((time.time() - start_time) * 1000, 2) # em milissegundos
        
        cur.close()
        conn.close()
        
        # Análise e Validação dos Resultados
        validation_info = analyze_results(rows, columns, raw_sql)
        
        return jsonify({
            "success": True,
            "columns": columns,
            "rows": rows,
            "row_count": len(rows),
            "execution_time_ms": elapsed_time,
            "processed_sql": processed_sql,
            "validation": validation_info
        })
        
    except Exception as e:
        elapsed_time = round((time.time() - start_time) * 1000, 2)
        return jsonify({
            "success": False,
            "error": str(e),
            "execution_time_ms": elapsed_time,
            "processed_sql": processed_sql
        })

def analyze_results(rows, columns, raw_sql):
    """
    Gera validações automáticas sobre os resultados obtidos.
    """
    alerts = []
    summary = {}
    
    if not rows:
        alerts.append({
            "type": "warning",
            "title": "Nenhum registro retornado",
            "message": "A consulta executou com sucesso, mas a busca não retornou dados para os parâmetros informados."
        })
        return {"alerts": alerts, "summary": summary}

    # 1. Detecção de colunas numéricas para somatório
    numeric_cols = []
    for col in columns:
        sample_vals = [r[col] for r in rows if r[col] is not None]
        if sample_vals and all(isinstance(v, (int, float)) for v in sample_vals):
            numeric_cols.append(col)
            
    # 2. Verificação de UNION ALL com totalizadores (Opção A)
    has_union_total = False
    total_labels_found = []
    
    for r in rows:
        for col_name, val in r.items():
            if isinstance(val, str) and ("TOTAL" in val.upper() or "TOTALIZADOR" in val.upper()):
                has_union_total = True
                total_labels_found.append(val)
                
    if has_union_total:
        alerts.append({
            "type": "info",
            "title": "Linhas Totalizadoras Detectadas (UNION ALL)",
            "message": f"Identificamos que o resultado possui linhas de resumo agrupadas ({', '.join(set(total_labels_found[:3]))}). Atenção: Não some a coluna inteira para evitar duplicidade!"
        })
        
    # 3. Verificação de valores NULL em colunas chave
    null_counts = {}
    for col in columns:
        nulls = sum(1 for r in rows if r[col] is None)
        if nulls > 0:
            null_counts[col] = nulls
            
    if null_counts:
        cols_str = ", ".join([f"{k} ({v} nulos)" for k, v in null_counts.items()])
        alerts.append({
            "type": "warning",
            "title": "Valores Nulos (NULL) Encontrados",
            "message": f"Campos com valores ausentes: {cols_str}. Verifique se é necessário tratar com COALESCE ou ajuste nos JOINs."
        })
        
    summary["numeric_columns"] = numeric_cols
    summary["null_counts"] = null_counts
    
    return {"alerts": alerts, "summary": summary}

if __name__ == '__main__':
    print("Iniciando Autosystem SQL Tester Web App em http://0.0.0.0:5000 ...")
    print("Acessível na rede local em: http://192.168.0.123:5000")
    app.run(host='0.0.0.0', port=5000, debug=True)

