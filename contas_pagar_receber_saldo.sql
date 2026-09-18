-- ==============================================================================
-- PROJETO IA AUTOSYSTEM - RELATÓRIOS FINANCEIROS
-- Script: contas_pagar_receber_saldo.sql
-- Descrição: Consultas de Saldos em Aberto de Contas a Pagar e Contas a Receber
-- Regras Contábeis Validadas:
--   - Contas a Pagar (PASSIVO 2.1.1): Nascem no Crédito, baixam no Débito.
--   - Contas a Receber (ATIVO 1.3.x): Nascem no Débito, baixam no Crédito.
-- Parâmetros no Autosystem:
--   $empresa (ex: 7)
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. CONTAS A PAGAR - SALDO EM ABERTO POR FORNECEDOR (Conta 2.1.1 - PASSIVO)
-- ------------------------------------------------------------------------------
SELECT 
    p.codigo AS codigo_fornecedor,
    COALESCE(p.nome, 'FORNECEDOR NAO IDENTIFICADO') AS fornecedor,
    p.cpf AS cnpj_cpf,
    SUM(CASE WHEN m.conta_creditar = '2.1.1' THEN m.valor ELSE 0 END) AS total_gerado_credito,
    SUM(CASE WHEN m.conta_debitar  = '2.1.1' THEN m.valor ELSE 0 END) AS total_pago_debito,
    (SUM(CASE WHEN m.conta_creditar = '2.1.1' THEN m.valor ELSE 0 END) -
     SUM(CASE WHEN m.conta_debitar  = '2.1.1' THEN m.valor ELSE 0 END)) AS saldo_em_aberto
FROM movto m
LEFT JOIN pessoa p ON m.pessoa = p.grid
WHERE m.empresa = $empresa
  AND ('2.1.1' IN (m.conta_creditar, m.conta_debitar))
GROUP BY p.codigo, p.nome, p.cpf
HAVING (SUM(CASE WHEN m.conta_creditar = '2.1.1' THEN m.valor ELSE 0 END) -
        SUM(CASE WHEN m.conta_debitar  = '2.1.1' THEN m.valor ELSE 0 END)) <> 0
ORDER BY saldo_em_aberto DESC;

-- ------------------------------------------------------------------------------
-- 2. CONTAS A RECEBER - SALDO EM ABERTO POR CONTA E CLIENTE (Contas 1.3.x - ATIVO)
-- ------------------------------------------------------------------------------
SELECT 
    c.codigo AS codigo_conta,
    c.nome AS nome_conta_forma,
    p.codigo AS codigo_cliente,
    COALESCE(p.nome, 'SEM PESSOA VINCULADA (CARTÃO/PIX/ADM)') AS cliente,
    SUM(CASE WHEN m.conta_debitar LIKE '1.3%' THEN m.valor ELSE 0 END) AS total_gerado_debito,
    SUM(CASE WHEN m.conta_creditar LIKE '1.3%' THEN m.valor ELSE 0 END) AS total_baixado_credito,
    (SUM(CASE WHEN m.conta_debitar LIKE '1.3%' THEN m.valor ELSE 0 END) -
     SUM(CASE WHEN m.conta_creditar LIKE '1.3%' THEN m.valor ELSE 0 END)) AS saldo_em_aberto
FROM movto m
JOIN conta c ON (m.conta_debitar = c.codigo OR m.conta_creditar = c.codigo) AND c.tipo_conta_receber = true
LEFT JOIN pessoa p ON m.pessoa = p.grid
WHERE m.empresa = $empresa
GROUP BY c.codigo, c.nome, p.codigo, p.nome
HAVING (SUM(CASE WHEN m.conta_debitar LIKE '1.3%' THEN m.valor ELSE 0 END) -
        SUM(CASE WHEN m.conta_creditar LIKE '1.3%' THEN m.valor ELSE 0 END)) <> 0
ORDER BY c.codigo, saldo_em_aberto DESC;

-- ------------------------------------------------------------------------------
-- 3. RESUMO AGREGADO DE CONTAS A RECEBER POR FORMA/CONTA
-- ------------------------------------------------------------------------------
SELECT 
    c.codigo AS codigo_conta,
    c.nome AS nome_conta,
    COUNT(DISTINCT m.pessoa) AS qtd_clientes,
    (SUM(CASE WHEN m.conta_debitar = c.codigo THEN m.valor ELSE 0 END) -
     SUM(CASE WHEN m.conta_creditar = c.codigo THEN m.valor ELSE 0 END)) AS saldo_total_aberto
FROM movto m
JOIN conta c ON (m.conta_debitar = c.codigo OR m.conta_creditar = c.codigo) AND c.tipo_conta_receber = true
WHERE m.empresa = $empresa
GROUP BY c.codigo, c.nome
HAVING (SUM(CASE WHEN m.conta_debitar = c.codigo THEN m.valor ELSE 0 END) -
        SUM(CASE WHEN m.conta_creditar = c.codigo THEN m.valor ELSE 0 END)) <> 0
ORDER BY c.codigo;
