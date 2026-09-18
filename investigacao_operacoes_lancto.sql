-- ==============================================================================
-- PROJETO IA AUTOSYSTEM - SCRIPT DE INVESTIGAÇÃO & VALIDAÇÕES PENDENTES
-- Script: investigacao_operacoes_lancto.sql
-- Descrição: Consultas para resolver pendências de validação (operacao 'E', 'M', encerrantes e LMC)
-- Parâmetros no Autosystem:
--   $empresa        (ex: 7)
--   $dt_periodo_ini (ex: '2026-07-01')
--   $dt_periodo_fim (ex: '2026-07-28')
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. INVESTIGAR OPERAÇÃO 'E' NA TABELA LANCTO (Entradas/Trocas/Ajustes)
-- ------------------------------------------------------------------------------
SELECT 
    l.operacao,
    l.data,
    l.hora,
    p.nome AS produto,
    l.quantidade,
    l.preco_unit,
    l.valor,
    l.obs,
    l.pessoa,
    l.mlid
FROM lancto l
LEFT JOIN produto p ON l.produto = p.grid
WHERE l.empresa = $empresa
  AND l.data BETWEEN $dt_periodo_ini AND $dt_periodo_fim
  AND l.operacao = 'E'
ORDER BY l.data DESC
LIMIT 30;

-- ------------------------------------------------------------------------------
-- 2. INVESTIGAR OPERAÇÃO 'M' NA TABELA LANCTO (Movimentação Interna / Manual)
-- ------------------------------------------------------------------------------
SELECT 
    l.operacao,
    l.data,
    l.hora,
    p.nome AS produto,
    l.quantidade,
    l.preco_unit,
    l.valor,
    l.obs,
    l.pessoa,
    l.mlid
FROM lancto l
LEFT JOIN produto p ON l.produto = p.grid
WHERE l.empresa = $empresa
  AND l.data BETWEEN $dt_periodo_ini AND $dt_periodo_fim
  AND l.operacao = 'M'
ORDER BY l.data DESC
LIMIT 30;

-- ------------------------------------------------------------------------------
-- 3. VERIFICAR SE A TABELA BICO_ENCERRANTE POSSUI DADOS NO AMBIENTE
-- ------------------------------------------------------------------------------
SELECT 
    bico,
    encerrante,
    ts,
    flag,
    last_str
FROM bico_encerrante
ORDER BY ts DESC
LIMIT 30;

-- ------------------------------------------------------------------------------
-- 4. TESTAR DISPONIBILIDADE DAS TABELAS DE LMC (Livro de Movimentação de Combustível)
-- ------------------------------------------------------------------------------
SELECT 
    l.folha,
    l.data,
    p.nome AS produto,
    lv.bico,
    lv.quantidade,
    lv.afericao,
    lv.enc_fim
FROM lmc l
JOIN lmc_venda lv ON l.grid = lv.lmc
LEFT JOIN produto p ON l.produto = p.grid
WHERE l.empresa = $empresa
  AND l.data BETWEEN $dt_periodo_ini AND $dt_periodo_fim
ORDER BY l.data DESC, lv.bico
LIMIT 30;

-- ------------------------------------------------------------------------------
-- 5. COMPARATIVO DE AUDITORIA DE ENCERRANTES (lancto vs. bico_encerrante)
-- ------------------------------------------------------------------------------
SELECT 
    l.bico,
    p.nome AS combustivel,
    MIN(l.encerrante) AS enc_min_lancto,
    MAX(l.encerrante) AS enc_max_lancto,
    SUM(l.quantidade) AS total_volume_lancto
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
