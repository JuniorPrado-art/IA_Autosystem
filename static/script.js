document.addEventListener('DOMContentLoaded', () => {
    // UI Elements
    const dbHostInput = document.getElementById('db-host');
    const dbPortInput = document.getElementById('db-port');
    const dbNameInput = document.getElementById('db-name');
    const dbUserInput = document.getElementById('db-user');
    const dbPasswordInput = document.getElementById('db-password');
    const dbStatusBadge = document.getElementById('db-status-badge');
    const btnTestDb = document.getElementById('btn-test-db');

    const fileSelect = document.getElementById('file-select');
    const btnRefreshFiles = document.getElementById('btn-refresh-files');
    const currentFilename = document.getElementById('current-filename');
    const paramsContainer = document.getElementById('params-container');

    const sqlEditor = document.getElementById('sql-editor');
    const lineNumbers = document.getElementById('line-numbers');
    const lineCounterBadge = document.getElementById('line-counter-badge');

    function updateLineNumbers() {
        if (!sqlEditor || !lineNumbers) return;
        const lines = sqlEditor.value.split('\n');
        const count = lines.length;
        let numbersText = '';
        for (let i = 1; i <= count; i++) {
            numbersText += i + '\n';
        }
        lineNumbers.textContent = numbersText;
        if (lineCounterBadge) {
            lineCounterBadge.textContent = `Linhas: ${count}`;
        }
    }

    if (sqlEditor && lineNumbers) {
        sqlEditor.addEventListener('scroll', () => {
            lineNumbers.scrollTop = sqlEditor.scrollTop;
        });
        sqlEditor.addEventListener('input', updateLineNumbers);
        sqlEditor.addEventListener('keyup', updateLineNumbers);
        sqlEditor.addEventListener('change', updateLineNumbers);
        sqlEditor.addEventListener('mouseup', updateLineNumbers);
    }

    const btnRunSql = document.getElementById('btn-run-sql');
    const btnFormatSql = document.getElementById('btn-format-sql');
    const btnCopySql = document.getElementById('btn-copy-sql');

    const snippetsBar = document.getElementById('snippets-bar');
    const snippetsList = document.getElementById('snippets-list');

    const statusSection = document.getElementById('status-section');
    const execStatus = document.getElementById('exec-status');
    const execRows = document.getElementById('exec-rows');
    const execTime = document.getElementById('exec-time');
    const validationAlerts = document.getElementById('validation-alerts');
    const errorBox = document.getElementById('error-box');
    const errorText = document.getElementById('error-text');

    const resultsTable = document.getElementById('results-table');
    const tableHead = document.getElementById('table-head');
    const tableBody = document.getElementById('table-body');
    const tableSearch = document.getElementById('table-search');
    const btnExportCsv = document.getElementById('btn-export-csv');
    const btnExportJson = document.getElementById('btn-export-json');

    let currentRowsData = [];
    let currentColumnsData = [];
    let detectedParamsMap = {};

    // 1. Connection Config Management
    function getDbConfigFromInputs() {
        return {
            host: dbHostInput ? dbHostInput.value : 'localhost',
            port: dbPortInput ? dbPortInput.value : '5432',
            dbname: dbNameInput ? dbNameInput.value : 'autosystem',
            user: dbUserInput ? dbUserInput.value : 'postgres',
            password: dbPasswordInput ? dbPasswordInput.value : ''
        };
    }

    function saveConfigToLocalStorage() {
        try {
            const config = getDbConfigFromInputs();
            localStorage.setItem('autosystem_db_config', JSON.stringify(config));
        } catch (e) {
            console.warn("Não foi possível salvar configurações no localStorage:", e);
        }
    }

    async function loadConfig() {
        try {
            const localSaved = localStorage.getItem('autosystem_db_config');
            let data = null;
            if (localSaved) {
                try { data = JSON.parse(localSaved); } catch (e) {}
            }
            if (!data) {
                const res = await fetch('/api/config');
                data = await res.json();
            }
            if (data) {
                if (data.host !== undefined && dbHostInput) dbHostInput.value = data.host;
                if (data.port !== undefined && dbPortInput) dbPortInput.value = data.port;
                if (data.dbname !== undefined && dbNameInput) dbNameInput.value = data.dbname;
                if (data.user !== undefined && dbUserInput) dbUserInput.value = data.user;
                if (data.password !== undefined && dbPasswordInput) dbPasswordInput.value = data.password;
            }
        } catch (err) {
            console.error("Erro ao carregar configurações de banco:", err);
        }
    }

    // Monitorar alterações nos campos de banco para resetar cache de empresas e salvar localmente
    [dbHostInput, dbPortInput, dbNameInput, dbUserInput, dbPasswordInput].forEach(elem => {
        if (elem) {
            elem.addEventListener('change', () => {
                loadedEmpresas = [];
                saveConfigToLocalStorage();
            });
        }
    });

    async function testConnection() {
        const config = getDbConfigFromInputs();

        btnTestDb.disabled = true;
        btnTestDb.textContent = 'Testando...';

        try {
            const res = await fetch('/api/test-db', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(config)
            });
            const data = await res.json();

            if (data.success) {
                dbStatusBadge.textContent = 'Conectado';
                dbStatusBadge.className = 'badge badge-success';
                saveConfigToLocalStorage();
                loadedEmpresas = [];
            } else {
                dbStatusBadge.textContent = 'Erro de Conexão';
                dbStatusBadge.className = 'badge badge-danger';
                alert('Erro ao conectar no PostgreSQL: ' + data.error);
            }
        } catch (err) {
            dbStatusBadge.textContent = 'Erro de Conexão';
            dbStatusBadge.className = 'badge badge-danger';
            alert('Falha na requisição de conexão.');
        } finally {
            btnTestDb.disabled = false;
            btnTestDb.textContent = 'Testar e Salvar Conexão';
        }
    }

    btnTestDb.addEventListener('click', testConnection);

    // 2. Load Workspace Files
    async function loadFiles() {
        try {
            const res = await fetch('/api/files');
            const files = await res.json();
            
            fileSelect.innerHTML = '<option value="">-- Selecione um arquivo SQL --</option>';
            files.forEach(f => {
                const opt = document.createElement('option');
                opt.value = f.path;
                opt.textContent = `${f.name} (${f.ext})`;
                fileSelect.appendChild(opt);
            });
        } catch (err) {
            fileSelect.innerHTML = '<option value="">Erro ao carregar arquivos</option>';
        }
    }

    btnRefreshFiles.addEventListener('click', loadFiles);

    fileSelect.addEventListener('change', async () => {
        const selectedPath = fileSelect.value;
        if (!selectedPath) return;

        let data;
        try {
            const res = await fetch('/api/file-content', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ path: selectedPath })
            });
            data = await res.json();
        } catch (err) {
            alert('Falha de rede ao carregar o arquivo: ' + err.message);
            return;
        }

        if (data && data.content) {
            currentFilename.textContent = selectedPath;
            sqlEditor.value = data.content;
            updateLineNumbers();

            try {
                await detectQuerySnippets(data.content);
            } catch (e1) {
                console.warn("Erro ao analisar seções do arquivo:", e1);
            }

            try {
                await updateParametersFromSql(data.content);
            } catch (e2) {
                console.warn("Erro ao carregar parâmetros do arquivo:", e2);
            }
        } else if (data && data.error) {
            alert('Erro ao carregar arquivo: ' + data.error);
        }
    });


    const sectionDocCard = document.getElementById('section-doc-card');
    const docCardTitle = document.getElementById('doc-card-title');
    const docCardDesc = document.getElementById('doc-card-desc');

    // 3. Detect SQL Blocks/Snippets & Text Descriptions inside mixed text files
    async function detectQuerySnippets(text) {
        snippetsList.innerHTML = '';
        try {
            const res = await fetch('/api/parse-sections', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ content: text })
            });
            const data = await res.json();
            const sections = data.sections || [];

            if (sections.length > 0) {
                snippetsBar.classList.remove('hidden');
                
                sections.forEach((sec, idx) => {
                    const chip = document.createElement('div');
                    chip.className = 'chip' + (idx === 0 ? ' active' : '');
                    chip.textContent = sec.title.length > 35 ? sec.title.substring(0, 35) + '...' : sec.title;
                    chip.title = sec.title;

                    chip.addEventListener('click', () => {
                        document.querySelectorAll('.chip').forEach(c => c.classList.remove('active'));
                        chip.classList.add('active');

                        sqlEditor.value = sec.sql;
                        updateLineNumbers();
                        updateDocCard(sec.title, sec.description);
                        updateParametersFromSql(sec.sql);
                    });

                    snippetsList.appendChild(chip);
                });

                // Ativar e carregar a primeira consulta por padrão no editor e nos parâmetros
                const firstSec = sections[0];
                sqlEditor.value = firstSec.sql;
                updateLineNumbers();
                updateDocCard(firstSec.title, firstSec.description);
                await updateParametersFromSql(firstSec.sql);
            } else {
                snippetsBar.classList.add('hidden');
                sectionDocCard.classList.add('hidden');
            }
        } catch (err) {
            console.error("Erro ao analisar seções do texto:", err);
        }
    }


    function updateDocCard(title, description) {
        if (title || description) {
            docCardTitle.textContent = title || 'Descrição do Bloco';
            docCardDesc.textContent = description || 'Sem descrição adicional para esta consulta.';
            sectionDocCard.classList.remove('hidden');
        } else {
            sectionDocCard.classList.add('hidden');
        }
    }


    let loadedEmpresas = [];

    async function fetchEmpresas() {
        if (loadedEmpresas.length > 0) return loadedEmpresas;
        const config = getDbConfigFromInputs();
        try {
            const res = await fetch('/api/empresas', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(config)
            });
            const data = await res.json();
            if (data.success && data.empresas) {
                loadedEmpresas = data.empresas;
            }
        } catch (err) {
            console.warn("Não foi possível carregar a lista de empresas do banco:", err);
        }
        return loadedEmpresas;
    }

    async function updateParametersFromSql(sqlText) {
        try {
            const res = await fetch('/api/parse-params', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ sql: sqlText || '' })
            });
            const data = await res.json();
            let params = data.params || [];
            
            // Se o snippet individual não possuir parâmetros detectados, tentar varrer o editor completo
            if (params.length === 0 && sqlEditor && sqlEditor.value && sqlEditor.value !== sqlText) {
                const fullRes = await fetch('/api/parse-params', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ sql: sqlEditor.value })
                });
                const fullData = await fullRes.json();
                params = fullData.params || [];
            }

            // Se mesmo assim não detectar parâmetros por conta de formatação, garantir os parâmetros padrão do Autosystem
            if (params.length === 0) {
                const combined = (sqlText + ' ' + (sqlEditor ? sqlEditor.value : '')).toLowerCase();
                if (combined.includes('empresa') || combined.includes('movto') || combined.includes('data')) {
                    params = ['empresa', 'dt_periodo_ini', 'dt_periodo_fim'];
                }
            }

            await renderParametersForm(params);
        } catch (err) {
            console.error("Erro ao carregar e atualizar parâmetros:", err);
        }
    }

    async function renderParametersForm(params) {
        paramsContainer.innerHTML = '';
        if (params.length === 0) {
            paramsContainer.innerHTML = '<p class="text-muted small">Nenhum parâmetro dinâmico ($var ou :var) detectado na query atual.</p>';
            return;
        }

        const empresas = await fetchEmpresas();

        params.forEach(p => {
            const group = document.createElement('div');
            group.className = 'form-group';
            
            const label = document.createElement('label');
            const keyLower = p.toLowerCase();

            // Rotulagem amigável em português
            if (keyLower.includes('empresa')) {
                label.textContent = `🏢 Empresa / Filial ($${p})`;
            } else if (keyLower.includes('ini') || keyLower.includes('inicial')) {
                label.textContent = `📅 Data Inicial ($${p})`;
            } else if (keyLower.includes('fim') || keyLower.includes('final')) {
                label.textContent = `📅 Data Final ($${p})`;
            } else if (keyLower.includes('data') || keyLower.includes('dt') || keyLower.includes('periodo')) {
                label.textContent = `📅 Data ($${p})`;
            } else {
                label.textContent = `⚙️ Parâmetro ($${p})`;
            }

            let input;

            if (keyLower.includes('empresa') && empresas.length > 0) {
                input = document.createElement('select');
                input.className = 'form-control';
                
                let selectedMatched = false;
                empresas.forEach(emp => {
                    const opt = document.createElement('option');
                    opt.value = emp.grid; // Usar o GRID ID exigido pelo banco em movto.empresa (ex: 14572 para Filial 5)
                    opt.textContent = `Filial ${emp.codigo} - ${emp.nome}`;
                    
                    const savedVal = detectedParamsMap[p];
                    if (savedVal && (String(savedVal) === String(emp.grid) || String(savedVal) === String(emp.codigo))) {
                        opt.selected = true;
                        selectedMatched = true;
                    } else if (!savedVal && !selectedMatched && (emp.codigo === 5 || emp.codigo === '5' || emp.grid === 14572)) {
                        opt.selected = true;
                        selectedMatched = true;
                    }
                    input.appendChild(opt);
                });

                if (!selectedMatched && input.options.length > 0) {
                    input.options[0].selected = true;
                }
            } else if (keyLower.includes('data') || keyLower.includes('dt') || keyLower.includes('periodo')) {
                input = document.createElement('input');
                input.type = 'date';
                input.className = 'form-control';

                if (keyLower.includes('ini') || keyLower.includes('inicial')) {
                    input.value = detectedParamsMap[p] || '2026-07-01';
                } else if (keyLower.includes('fim') || keyLower.includes('final')) {
                    input.value = detectedParamsMap[p] || '2026-07-31';
                } else {
                    input.value = detectedParamsMap[p] || '2026-07-01';
                }
            } else {
                input = document.createElement('input');
                input.type = keyLower.includes('empresa') ? 'number' : 'text';
                input.className = 'form-control';
                input.value = detectedParamsMap[p] || (keyLower.includes('empresa') ? '14572' : '');
            }

            input.id = `param-input-${p}`;
            input.dataset.paramKey = p;
            
            // Guardar valor atualizado sempre que o usuário alterar
            input.addEventListener('change', (e) => {
                detectedParamsMap[p] = e.target.value;
            });
            input.addEventListener('input', (e) => {
                detectedParamsMap[p] = e.target.value;
            });

            detectedParamsMap[p] = input.value;

            group.appendChild(label);
            group.appendChild(input);
            paramsContainer.appendChild(group);
        });
    }

    // Monitorar digitação no editor de código para atualizar parâmetros dinamicamente
    let debounceTimer;
    sqlEditor.addEventListener('input', () => {
        clearTimeout(debounceTimer);
        debounceTimer = setTimeout(() => {
            updateParametersFromSql(sqlEditor.value);
        }, 500);
    });

    const btnOpenNewTab = document.getElementById('btn-open-new-tab');

    // 5. Execute SQL & Process Results
    async function executeQuery(openInNewTab = false) {
        const sqlText = sqlEditor.value.trim();
        if (!sqlText) {
            alert('Por favor, informe ou selecione uma consulta SQL.');
            return;
        }

        // Coletar parâmetros atuais dos inputs e selects
        const currentParamValues = {};
        const paramElements = paramsContainer.querySelectorAll('[data-param-key]');
        paramElements.forEach(elem => {
            currentParamValues[elem.dataset.paramKey] = elem.value;
        });

        const config = getDbConfigFromInputs();

        btnRunSql.disabled = true;
        btnRunSql.innerHTML = '<span class="btn-icon">⏳</span> Executando...';
        if (btnOpenNewTab) btnOpenNewTab.disabled = true;

        errorBox.classList.add('hidden');
        statusSection.classList.add('hidden');

        try {
            const res = await fetch('/api/execute-sql', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    sql: sqlText,
                    params: currentParamValues,
                    config: config
                })
            });

            const data = await res.json();

            if (data.success) {
                execStatus.textContent = 'Sucesso';
                execStatus.className = 'metric-value text-success';
                execRows.textContent = data.row_count;
                execTime.textContent = `${data.execution_time_ms} ms`;

                renderValidationAlerts(data.validation);
                statusSection.classList.remove('hidden');

                currentColumnsData = data.columns || [];
                currentRowsData = data.rows || [];
                renderResultsTable(currentColumnsData, currentRowsData);

                btnExportCsv.disabled = currentRowsData.length === 0;
                btnExportJson.disabled = currentRowsData.length === 0;

                // Salvar resultado no localStorage para a página dedicada /resultado
                const activeChip = document.querySelector('.chip.active');
                const reportPayload = {
                    rows: currentRowsData,
                    columns: currentColumnsData,
                    execution_time_ms: data.execution_time_ms,
                    validation: data.validation,
                    params: currentParamValues,
                    title: activeChip ? activeChip.title : (docCardTitle ? docCardTitle.textContent : 'Relatório de Resultados PostgreSQL'),
                    description: docCardDesc ? docCardDesc.textContent : '',
                    fileName: currentFilename ? currentFilename.textContent : ''
                };
                localStorage.setItem('autosystem_last_result', JSON.stringify(reportPayload));

                if (openInNewTab) {
                    window.open('/resultado', '_blank');
                }
            } else {
                errorText.textContent = data.error;
                errorBox.classList.remove('hidden');
                
                execStatus.textContent = 'Erro';
                execStatus.className = 'metric-value text-danger';
                execRows.textContent = '0';
                execTime.textContent = `${data.execution_time_ms || 0} ms`;

                // Detectar número da linha do erro PostgreSQL (ex: LINE 34:)
                const lineMatch = (data.error || '').match(/LINE\s+(\d+):/i);
                if (lineMatch) {
                    const errLine = lineMatch[1];
                    validationAlerts.innerHTML = `
                        <div class="alert alert-danger" style="background: rgba(239, 68, 68, 0.15); border: 1px solid #ef4444; color: #f87171; padding: 0.6rem 1rem; border-radius: 6px; font-weight: 600;">
                            📍 <strong>Erro de Sintaxe na Linha ${errLine}:</strong> Verifique a linha ${errLine} no editor de código acima.
                        </div>
                    `;
                } else {
                    validationAlerts.innerHTML = '';
                }
                statusSection.classList.remove('hidden');

                renderResultsTable([], []);
                btnExportCsv.disabled = true;
                btnExportJson.disabled = true;
            }
        } catch (err) {
            errorText.textContent = 'Falha crítica na requisição: ' + err.message;
            errorBox.classList.remove('hidden');
        } finally {
            btnRunSql.disabled = false;
            btnRunSql.innerHTML = '<span class="btn-icon">▶</span> Executar SQL';
            if (btnOpenNewTab) btnOpenNewTab.disabled = false;
        }
    }

    btnRunSql.addEventListener('click', () => executeQuery(false));
    if (btnOpenNewTab) {
        btnOpenNewTab.addEventListener('click', () => executeQuery(true));
    }


    btnFormatSql.addEventListener('click', () => {
        sqlEditor.value = '';
        updateLineNumbers();
        currentFilename.textContent = 'Nova Consulta SQL';
        paramsContainer.innerHTML = '<p class="text-muted small">Digite sua query SQL acima.</p>';
        snippetsBar.classList.add('hidden');
    });

    btnCopySql.addEventListener('click', () => {
        if (!sqlEditor.value) return;
        navigator.clipboard.writeText(sqlEditor.value);
        alert('Código SQL copiado para a área de transferência!');
    });

    // 6. Validation Alerts Renderer
    function renderValidationAlerts(validation) {
        validationAlerts.innerHTML = '';
        if (!validation || !validation.alerts || validation.alerts.length === 0) return;

        validation.alerts.forEach(al => {
            const alertDiv = document.createElement('div');
            alertDiv.className = `alert alert-${al.type}`;
            alertDiv.innerHTML = `<strong>${al.title}:</strong> ${al.message}`;
            validationAlerts.appendChild(alertDiv);
        });
    }

    // 7. Render Interactive Results Table
    function renderResultsTable(columns, rows) {
        tableHead.innerHTML = '';
        tableBody.innerHTML = '';

        if (columns.length === 0) {
            tableHead.innerHTML = '<th>Status</th>';
            tableBody.innerHTML = '<tr><td class="text-center text-muted">Nenhum dado retornado.</td></tr>';
            return;
        }

        // Head
        columns.forEach(col => {
            const th = document.createElement('th');
            th.textContent = col;
            tableHead.appendChild(th);
        });

        // Body
        if (rows.length === 0) {
            const tr = document.createElement('tr');
            const td = document.createElement('td');
            td.colSpan = columns.length;
            td.className = 'text-center text-muted';
            td.textContent = 'Consulta retornou 0 resultados.';
            tr.appendChild(td);
            tableBody.appendChild(tr);
            return;
        }

        rows.forEach(r => {
            const tr = document.createElement('tr');
            
            // Destacar linhas que parecem ser totais
            let isTotalRow = false;
            columns.forEach(col => {
                const valStr = String(r[col] || '').toUpperCase();
                if (valStr.includes('TOTAL') || valStr.includes('TOTALIZADOR')) {
                    isTotalRow = true;
                }
            });
            if (isTotalRow) tr.className = 'highlight-total';

            columns.forEach(col => {
                const td = document.createElement('td');
                const val = r[col];

                if (val === null || val === undefined) {
                    td.textContent = 'NULL';
                    td.className = 'text-muted small';
                } else if (typeof val === 'number') {
                    // Formatar número/moeda se a coluna indicar valor
                    if (col.toLowerCase().includes('valor') || col.toLowerCase().includes('total') || col.toLowerCase().includes('saldo') || col.toLowerCase().includes('entradas') || col.toLowerCase().includes('saidas')) {
                        td.textContent = val.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
                    } else {
                        td.textContent = val.toLocaleString('pt-BR');
                    }
                } else {
                    td.textContent = val;
                }

                tr.appendChild(td);
            });

            tableBody.appendChild(tr);
        });
    }

    // 8. Client-side Search Filter
    tableSearch.addEventListener('input', () => {
        const query = tableSearch.value.toLowerCase().trim();
        const trs = tableBody.querySelectorAll('tr');

        trs.forEach(tr => {
            const text = tr.textContent.toLowerCase();
            if (!query || text.includes(query)) {
                tr.style.display = '';
            } else {
                tr.style.display = 'none';
            }
        });
    });

    // 9. Export Functions
    btnExportCsv.addEventListener('click', () => {
        if (!currentRowsData || currentRowsData.length === 0) return;

        let csvContent = currentColumnsData.join(',') + '\n';
        currentRowsData.forEach(r => {
            const rowVals = currentColumnsData.map(col => {
                let v = r[col];
                if (v === null || v === undefined) return '""';
                v = String(v).replace(/"/g, '""');
                return `"${v}"`;
            });
            csvContent += rowVals.join(',') + '\n';
        });

        const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `autosystem_export_${Date.now()}.csv`;
        a.click();
        URL.revokeObjectURL(url);
    });

    btnExportJson.addEventListener('click', () => {
        if (!currentRowsData || currentRowsData.length === 0) return;

        const blob = new Blob([JSON.stringify(currentRowsData, null, 2)], { type: 'application/json' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `autosystem_export_${Date.now()}.json`;
        a.click();
        URL.revokeObjectURL(url);
    });

    // Init
    loadConfig();
    loadFiles();
    updateLineNumbers();
});
