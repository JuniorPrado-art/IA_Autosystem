-- ==============================================================================
-- PROJETO IA AUTOSYSTEM - RELATÓRIOS FINANCEIROS & FECHAMENTO DIÁRIO
-- Script: fechamento_por_periodo.sql
-- Descrição: Consultas parametrizadas por Empresa e Período para o Fechamento Diário
-- Parâmetros no Autosystem:
--   $empresa        (ex: 7)
--   $dt_periodo_ini (ex: '2026-07-01')
--   $dt_periodo_fim (ex: '2026-07-28')
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- SEÇÃO 1: RECEBIMENTOS POR FORMA DE PAGAMENTO
-- Consolidação dos recebimentos do caixa/movimento financeiro agrupados por forma
-- ------------------------------------------------------------------------------
SELECT 
    mm.nome AS forma_pagamento,
    COUNT(m.grid) AS qtd_lancamentos,
    SUM(m.valor) AS valor_total
FROM movto m
JOIN motivo_movto mm ON m.motivo = mm.grid
WHERE m.empresa = $empresa
  AND m.data BETWEEN $dt_periodo_ini AND $dt_periodo_fim
  AND mm.forma_pgto = true
GROUP BY mm.nome
ORDER BY valor_total DESC;

-- ------------------------------------------------------------------------------
-- SEÇÃO 2: RESUMO DE VENDAS - COMBUSTÍVEIS vs. PRODUTOS / SERVIÇOS
-- ------------------------------------------------------------------------------
SELECT 
    CASE 
        WHEN UPPER(gp.nome) = 'COMBUSTIVEL' THEN 'COMBUSTIVEIS'
        ELSE 'PRODUTOS E SERVICOS'
    END AS categoria_macro,
    SUM(l.quantidade) AS quantidade_total,
    SUM(l.valor) AS valor_total
FROM lancto l
JOIN produto p ON l.produto = p.grid
JOIN grupo_produto gp ON p.grupo = gp.grid
WHERE l.empresa = $empresa
  AND l.data BETWEEN $dt_periodo_ini AND $dt_periodo_fim
  AND l.operacao = 'V'
GROUP BY 
    CASE 
        WHEN UPPER(gp.nome) = 'COMBUSTIVEL' THEN 'COMBUSTIVEIS'
        ELSE 'PRODUTOS E SERVICOS'
    END;

-- ------------------------------------------------------------------------------
-- SEÇÃO 3: DETALHAMENTO DE VENDAS DE COMBUSTÍVEL POR PRODUTO
-- ------------------------------------------------------------------------------
SELECT 
    p.codigo AS codigo_produto,
    p.nome AS produto,
    p.unid_med,
    SUM(l.quantidade) AS volume_litros,
    ROUND(CAST(AVG(l.preco_unit) AS numeric), 3) AS preco_medio,
    SUM(l.valor) AS total_venda
FROM lancto l
JOIN produto p ON l.produto = p.grid
JOIN grupo_produto gp ON p.grupo = gp.grid
WHERE l.empresa = $empresa
  AND l.data BETWEEN $dt_periodo_ini AND $dt_periodo_fim
  AND l.operacao = 'V'
  AND UPPER(gp.nome) = 'COMBUSTIVEL'
GROUP BY p.codigo, p.nome, p.unid_med
ORDER BY total_venda DESC;

-- ------------------------------------------------------------------------------
-- SEÇÃO 4: DETALHAMENTO DE VENDAS POR BICO DE COMBUSTÍVEL
-- Encerrante Inicial e Final calculados por MIN/MAX no período em lancto
-- ------------------------------------------------------------------------------
SELECT 
    l.bico AS numero_bico,
    p.nome AS combustivel,
    MIN(l.encerrante) AS encerrante_inicial_aprox,
    MAX(l.encerrante) AS encerrante_final_aprox,
    SUM(l.quantidade) AS total_litros,
    SUM(l.valor) AS total_valor
FROM lancto l
JOIN produto p ON l.produto = p.grid
JOIN grupo_produto gp ON p.grupo = gp.grid
WHERE l.empresa = $empresa
  AND l.data BETWEEN $dt_periodo_ini AND $dt_periodo_fim
  AND l.operacao = 'V'
  AND UPPER(gp.nome) = 'COMBUSTIVEL'
  AND l.bico IS NOT NULL AND l.bico <> ''
GROUP BY l.bico, p.nome
ORDER BY l.bico;

-- ------------------------------------------------------------------------------
-- SEÇÃO 5: VENDAS DE PRODUTOS NÃO-COMBUSTÍVEIS POR CATEGORIA
-- ------------------------------------------------------------------------------
SELECT 
    gp.nome AS categoria,
    COUNT(DISTINCT l.produto) AS diversidade_produtos,
    SUM(l.quantidade) AS qtd_itens,
    SUM(l.valor) AS total_venda
FROM lancto l
JOIN produto p ON l.produto = p.grid
JOIN grupo_produto gp ON p.grupo = gp.grid
WHERE l.empresa = $empresa
  AND l.data BETWEEN $dt_periodo_ini AND $dt_periodo_fim
  AND l.operacao = 'V'
  AND UPPER(gp.nome) <> 'COMBUSTIVEL'
GROUP BY gp.nome
ORDER BY total_venda DESC;

-- ------------------------------------------------------------------------------
-- SEÇÃO 6: SANGRIA DE CAIXA
-- ------------------------------------------------------------------------------
SELECT 
    c.data AS data_caixa,
    c.turno,
    s.hora,
    s.valor,
    s.obs
FROM sangria s
JOIN caixa c ON s.caixa = c.grid
WHERE c.empresa = $empresa
  AND c.data BETWEEN $dt_periodo_ini AND $dt_periodo_fim
ORDER BY s.hora;

-- ------------------------------------------------------------------------------
-- SEÇÃO 7: DIFERENÇAS DE CAIXA (FALTAS / SOBRAS)
-- ------------------------------------------------------------------------------
SELECT 
    m.data,
    mm.nome AS tipo_diferenca,
    p.nome AS operador_caixa,
    m.valor,
    m.obs
FROM movto m
JOIN motivo_movto mm ON m.motivo = mm.grid
LEFT JOIN pessoa p ON m.pessoa = p.grid
WHERE m.empresa = $empresa
  AND m.data BETWEEN $dt_periodo_ini AND $dt_periodo_fim
  AND UPPER(mm.nome) IN ('FALTA DE CAIXA', 'SOBRA DE CAIXA')
ORDER BY m.data, m.hora;

-- ------------------------------------------------------------------------------
-- SEÇÃO 8: VENDAS A PRAZO DETALHADAS POR CLIENTE (NOTAS A PRAZO)
-- ------------------------------------------------------------------------------
SELECT 
    m.data,
    p.codigo AS codigo_cliente,
    p.nome AS cliente,
    p.cpf AS cpf_cnpj,
    m.documento AS numero_documento,
    m.valor AS valor_venda_prazo
FROM movto m
LEFT JOIN pessoa p ON m.pessoa = p.grid
WHERE m.empresa = $empresa
  AND m.data BETWEEN $dt_periodo_ini AND $dt_periodo_fim
  AND m.conta_debitar = '1.3.03'
ORDER BY p.nome, m.data;

-- ------------------------------------------------------------------------------
-- SEÇÃO 9: MOVIMENTAÇÃO DE COMBUSTÍVEIS / MEDIÇÃO DO PERÍODO (OPÇÃO M)
-- Consolidação do período (Início, Entrada, Venda, Aferição, Outros, Final, Medição e Diferença)
-- ------------------------------------------------------------------------------
WITH medicao_inicial_sub AS (
    SELECT DISTINCT ON (l.deposito)
        l.deposito,
        l.produto,
        l.quantidade AS volume_inicio
    FROM lancto l
    WHERE l.empresa = $empresa
      AND l.operacao = 'M'
      AND l.data < $dt_periodo_ini
    ORDER BY l.deposito, l.data DESC, l.turno DESC, l.hora DESC
),
estoque_inicial AS (
    SELECT 
        p.grid AS produto,
        SUM(
            COALESCE(
                mi.volume_inicio,
                produto_estoque_f($empresa::bigint, d.grid, p.grid, $dt_periodo_ini::date, 1, NULL),
                0
            )
        ) AS volume_inicio
    FROM produto p
    JOIN grupo_produto gp ON p.grupo = gp.grid
    JOIN deposito d ON d.empresa = $empresa AND d.produto = p.grid AND d.flag = 'A'
    LEFT JOIN medicao_inicial_sub mi ON mi.deposito = d.grid
    WHERE UPPER(gp.nome) = 'COMBUSTIVEL'
      AND p.controlar_estoque = true
    GROUP BY p.grid
),
movimentos_periodo AS (
    SELECT 
        l.produto,
        SUM(CASE WHEN l.operacao IN ('E', 'S', 'TE', 'DC', 'O') THEN l.quantidade ELSE 0 END) AS entrada,
        SUM(CASE WHEN l.operacao IN ('V', 'C', 'P', 'DF', 'TS', 'B') THEN l.quantidade ELSE 0 END) AS venda,
        SUM(CASE WHEN l.operacao = 'A' THEN l.quantidade ELSE 0 END) AS afericao,
        SUM(CASE WHEN l.operacao IN ('T', 'D') THEN l.quantidade ELSE 0 END) AS outros
    FROM lancto l
    WHERE l.empresa = $empresa
      AND l.data BETWEEN $dt_periodo_ini AND $dt_periodo_fim
    GROUP BY l.produto
),
medicao_final_sub AS (
    SELECT DISTINCT ON (l.deposito)
        l.deposito,
        l.produto,
        l.quantidade AS volume_medicao
    FROM lancto l
    WHERE l.empresa = $empresa
      AND l.operacao = 'M'
      AND l.data <= $dt_periodo_fim
    ORDER BY l.deposito, l.data DESC, l.turno DESC, l.hora DESC
),
medicao_periodo AS (
    SELECT 
        p.grid AS produto,
        SUM(COALESCE(mf.volume_medicao, 0)) AS volume_medicao
    FROM produto p
    JOIN grupo_produto gp ON p.grupo = gp.grid
    JOIN deposito d ON d.empresa = $empresa AND d.produto = p.grid AND d.flag = 'A'
    LEFT JOIN medicao_final_sub mf ON mf.deposito = d.grid
    WHERE UPPER(gp.nome) = 'COMBUSTIVEL'
      AND p.controlar_estoque = true
    GROUP BY p.grid
),
dados_consolidados AS (
    SELECT 
        p.codigo AS codigo_produto,
        p.nome AS produto,
        COALESCE(ei.volume_inicio, 0) AS inicio,
        COALESCE(mp.entrada, 0) AS entrada,
        COALESCE(mp.venda, 0) AS venda,
        COALESCE(mp.afericao, 0) AS afericao,
        COALESCE(mp.outros, 0) AS outros,
        -- Final = somatório do início + entradas - vendas
        (COALESCE(ei.volume_inicio, 0) + 
         COALESCE(mp.entrada, 0) - 
         COALESCE(mp.venda, 0)) AS final,
        COALESCE(med.volume_medicao, 0) AS medicao,
        -- Diferença = última medição registrada - final
        (COALESCE(med.volume_medicao, 0) - 
         (COALESCE(ei.volume_inicio, 0) + 
          COALESCE(mp.entrada, 0) - 
          COALESCE(mp.venda, 0))) AS diferenca
    FROM produto p
    JOIN grupo_produto gp ON p.grupo = gp.grid
    LEFT JOIN estoque_inicial ei ON ei.produto = p.grid
    LEFT JOIN movimentos_periodo mp ON mp.produto = p.grid
    LEFT JOIN medicao_periodo med ON med.produto = p.grid
    WHERE UPPER(gp.nome) = 'COMBUSTIVEL'
      AND p.controlar_estoque = true
)
SELECT 
    produto,
    inicio,
    entrada,
    venda,
    afericao,
    outros,
    final,
    medicao,
    diferenca
FROM dados_consolidados
WHERE inicio <> 0 
   OR entrada <> 0 
   OR venda <> 0 
   OR afericao <> 0 
   OR outros <> 0 
   OR medicao <> 0 
   OR final <> 0
ORDER BY produto;

