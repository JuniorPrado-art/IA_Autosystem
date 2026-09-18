-- ==============================================================================
-- PROJETO IA AUTOSYSTEM - CONSULTAS FORMATADAS PARA O EDITOR DE RELATÓRIOS
-- Arquivo: autosystem_editor_relatorio.sql
-- ==============================================================================

/*
================================================================================
1. CONFIGURAÇÃO DA ABA "TELA" (Desenho da tela XML no Autosystem)
================================================================================
Cole este código XML na aba "Tela":

<quadro titulo="Informações">
  <campo id="dt_periodo" modelo="periodo" valor_padrao="select to_char(current_date, 'yyyy-mm-01')::date, current_date" />
  <procura id="empresa" modelo="empresa" requerido="sim" titulo="Empresa" />
</quadro>

Variáveis geradas pelo Autosystem:
- Empresa:      $empresa
- Data Inicial: $dt_periodo_ini
- Data Final:   $dt_periodo_fim
*/


-- ==============================================================================
-- 2. CONSULTAS SQL PARA A ABA "Origem dos dados (SQL)"
-- Copie e cole a consulta desejada (SOMENTE O SQL, SEM TAGS XML)
-- ==============================================================================


-- ------------------------------------------------------------------------------
-- OPÇÃO A: RECEBIMENTOS POR FORMA DE PAGAMENTO (COM TOTAIS DE CARTÃO CRÉDITO E DÉBITO)
-- ------------------------------------------------------------------------------
WITH dados_base AS (
    SELECT 
        m.grid,
        m.valor,
        mm.nome AS forma_pagamento,
        -- Identificação da Categoria (CREDITO vs DEBITO)
        CASE 
            WHEN t.operacao = 'CREDIT' THEN 'CREDITO'
            WHEN t.operacao = 'DEBIT' THEN 'DEBITO'
            WHEN mm.tipo_cartao = 0 THEN 'CREDITO'
            WHEN mm.tipo_cartao = 1 THEN 'DEBITO'
            WHEN UPPER(mm.nome) LIKE '%ELECTRON%' OR UPPER(mm.nome) LIKE '%DEBIT%' THEN 'DEBITO'
            WHEN UPPER(mm.nome) LIKE '%CREDIT%' THEN 'CREDITO'
            ELSE NULL
        END AS categoria_cartao,
        -- Identificação da Credenciadora RECECARD S/A (Código 025)
        CASE 
            -- Condição Principal: Tabela tef_credenciadora / tef_credenciadora_config (Código 025 ou Nome RECECARD/REDECARD)
            WHEN mm.tef_credenciadora IN ('025', '25')
              OR tc.codigo IN ('025', '25')
              OR UPPER(COALESCE(tc.nome, '')) LIKE '%RECECARD%'
              OR UPPER(COALESCE(tc.nome, '')) LIKE '%REDECARD%'
              OR UPPER(mm.nome) LIKE '%RECECARD%'
              OR UPPER(mm.nome) LIKE '%REDECARD%' THEN TRUE
            -- Apoio Complementar: Tabela tef_transacao (operadora_nome)
            WHEN UPPER(COALESCE(t.operadora_nome, '')) LIKE '%RECECARD%'
              OR UPPER(COALESCE(t.operadora_nome, '')) LIKE '%REDECARD%' THEN TRUE
            ELSE FALSE
        END AS is_credenciadora_rececard,

        -- Identificação Unificada de PIX e QR Linx (Tipo NF-e/NFC-e 20/21 - Estático/Dinâmico, Info Adicional 34/35 ou QR Linx)
        CASE 
            WHEN mm.tipo_nfce IN ('20', '21', '22')
              OR CAST(mm.info_adic AS text) IN ('34', '35')
              OR UPPER(mm.nome) LIKE '%QR LINX%'
              OR UPPER(mm.nome) LIKE '%QRLINX%' THEN TRUE
            ELSE FALSE
        END AS is_credenciadora_pix_total
    FROM movto m
    JOIN motivo_movto mm ON m.motivo = mm.grid
    LEFT JOIN tef_transacao t ON t.movto = m.grid
    LEFT JOIN (
        SELECT CAST(codigo AS text) AS codigo, nome FROM tef_credenciadora
        UNION
        SELECT CAST(grid AS text) AS codigo, nome FROM tef_credenciadora_config
        UNION
        SELECT CAST(codigo AS text) AS codigo, nome FROM tef_credenciadora_config
    ) tc ON (CAST(mm.tef_credenciadora AS text) = CAST(tc.codigo AS text))
    WHERE m.empresa = $empresa
      AND m.data BETWEEN $dt_periodo_ini AND $dt_periodo_fim
      AND mm.forma_pgto = true
)
SELECT 
    forma_pagamento,
    qtd_lancamentos,
    valor_total
FROM (
    -- 1. Detalhamento de cada Forma de Pagamento individual
    SELECT 
        forma_pagamento, 
        COUNT(grid) AS qtd_lancamentos, 
        SUM(valor) AS valor_total, 
        1 AS ordem, 
        SUM(valor) AS ord_valor
    FROM dados_base
    GROUP BY forma_pagamento

    UNION ALL

    -- 2. Total Cartão de Crédito (Credenciadora RECECARD S/A - Código 025)
    SELECT 
        'Total Cartão de Crédito (RECECARD S/A)' AS forma_pagamento, 
        COUNT(grid) AS qtd_lancamentos, 
        COALESCE(SUM(valor), 0) AS valor_total, 
        2 AS ordem, 
        0 AS ord_valor
    FROM dados_base
    WHERE is_credenciadora_rececard = TRUE AND categoria_cartao = 'CREDITO'

    UNION ALL

    -- 3. Total Cartão de Débito (Credenciadora RECECARD S/A - Código 025)
    SELECT 
        'Total Cartão de Débito (RECECARD S/A)' AS forma_pagamento, 
        COUNT(grid) AS qtd_lancamentos, 
        COALESCE(SUM(valor), 0) AS valor_total, 
        3 AS ordem, 
        0 AS ord_valor
    FROM dados_base
    WHERE is_credenciadora_rececard = TRUE AND categoria_cartao = 'DEBITO'

    UNION ALL

    -- 4. TOTAL PIX (Tipo NF-e/NFC-e 20 ou Info Adicional 34)
    SELECT 
        'Total PIX (POS e QR Linx)' AS forma_pagamento, 
        COUNT(grid) AS qtd_lancamentos, 
        COALESCE(SUM(valor), 0) AS valor_total, 
        4 AS ordem, 
        0 AS ord_valor
    FROM dados_base
    WHERE is_credenciadora_pix_total = TRUE
) resultados
ORDER BY ordem ASC, ord_valor DESC;


-- ------------------------------------------------------------------------------
-- OPÇÃO B: RESUMO MACRO DE VENDAS (COMBUSTÍVEIS vs. PRODUTOS/SERVIÇOS)
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
-- OPÇÃO C: DETALHAMENTO DE VENDAS DE COMBUSTÍVEL POR PRODUTO
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
-- OPÇÃO D: DETALHAMENTO DE VENDAS POR BICO DE COMBUSTÍVEL
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
-- OPÇÃO E: VENDAS DA LOJA DE CONVENIÊNCIA POR CATEGORIA
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
-- OPÇÃO F: SANGRIA DE CAIXA (BUSCA EM SANGRIA E MOVTO)
-- ------------------------------------------------------------------------------
SELECT 
    c.data AS data_caixa,
    COALESCE(c.turno, 1) AS turno,
    s.hora,
    s.valor,
    COALESCE(s.obs, 'SANGRIA DE CAIXA') AS obs
FROM sangria s
JOIN caixa c ON s.caixa = c.grid
WHERE c.empresa = $empresa
  AND c.data BETWEEN $dt_periodo_ini AND $dt_periodo_fim

UNION ALL

SELECT 
    m.data AS data_caixa,
    1 AS turno,
    m.hora,
    m.valor,
    COALESCE(m.obs, mm.nome) AS obs
FROM movto m
JOIN motivo_movto mm ON m.motivo = mm.grid
WHERE m.empresa = $empresa
  AND m.data BETWEEN $dt_periodo_ini AND $dt_periodo_fim
  AND UPPER(mm.nome) LIKE '%SANGRIA%'

ORDER BY hora;



-- ------------------------------------------------------------------------------
-- OPÇÃO G: DIFERENÇAS DE CAIXA (FALTAS / SOBRAS)
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
-- OPÇÃO H: RESUMO DE VENDAS A PRAZO TOTALIZADO POR CLIENTE
-- ------------------------------------------------------------------------------
SELECT 
    p.codigo AS codigo_cliente,
    COALESCE(p.nome, 'CLIENTE NAO IDENTIFICADO') AS cliente,
    p.cpf AS cpf_cnpj,
    COUNT(m.grid) AS qtd_notas,
    SUM(m.valor) AS valor_total_prazo
FROM movto m
LEFT JOIN pessoa p ON m.pessoa = p.grid
WHERE m.empresa = $empresa
  AND m.data BETWEEN $dt_periodo_ini AND $dt_periodo_fim
  AND m.conta_debitar = '1.3.03'
GROUP BY p.codigo, p.nome, p.cpf
ORDER BY valor_total_prazo DESC;


-- ------------------------------------------------------------------------------
-- OPÇÃO I1: CONTAS A PAGAR - SALDO EM ABERTO CONSOLIDADO POR FORNECEDOR
-- (Calcula o saldo real líquido por Fornecedor: Créditos 2.1.1 - Débitos 2.1.1)
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
-- OPÇÃO I2: CONTAS A PAGAR - SALDO EM ABERTO DETALHADO POR FORNECEDOR E DOCUMENTO
-- (Consolida a nota e o pagamento por número de documento para mostrar saldo do título)
-- ------------------------------------------------------------------------------
SELECT 
    p.codigo AS codigo_fornecedor,
    COALESCE(p.nome, 'FORNECEDOR NAO IDENTIFICADO') AS fornecedor,
    p.cpf AS cnpj_cpf,
    COALESCE(NULLIF(m.documento, ''), 'SEM NUMERO') AS numero_documento,
    MIN(m.data) AS data_emissao,
    SUM(CASE WHEN m.conta_creditar = '2.1.1' THEN m.valor ELSE 0 END) AS total_gerado_credito,
    SUM(CASE WHEN m.conta_debitar  = '2.1.1' THEN m.valor ELSE 0 END) AS total_pago_debito,
    (SUM(CASE WHEN m.conta_creditar = '2.1.1' THEN m.valor ELSE 0 END) -
     SUM(CASE WHEN m.conta_debitar  = '2.1.1' THEN m.valor ELSE 0 END)) AS saldo_em_aberto
FROM movto m
LEFT JOIN pessoa p ON m.pessoa = p.grid
WHERE m.empresa = $empresa
  AND ('2.1.1' IN (m.conta_creditar, m.conta_debitar))
GROUP BY p.codigo, p.nome, p.cpf, COALESCE(NULLIF(m.documento, ''), 'SEM NUMERO')
HAVING (SUM(CASE WHEN m.conta_creditar = '2.1.1' THEN m.valor ELSE 0 END) -
        SUM(CASE WHEN m.conta_debitar  = '2.1.1' THEN m.valor ELSE 0 END)) <> 0
ORDER BY p.nome, data_emissao;


-- ------------------------------------------------------------------------------
-- OPÇÃO I3: CONTAS A PAGAR EM ABERTO - RESUMO CONSOLIDADO AGRUPADO POR CLIENTE / PESSOA (DESATIVADO)
-- (Filtra títulos de Contas a Pagar '2.1.1' ainda não baixados no período, calculando juros/multa)
-- ------------------------------------------------------------------------------
-- SELECT 
--     p.codigo AS codigo_cliente,
--     COALESCE(p.nome, 'PESSOA NAO IDENTIFICADA') AS cliente,
--     p.cpf AS cnpj_cpf,
--     COUNT(m.grid) AS qtd_titulos,
--     SUM(m.valor) AS valor_principal,
--     SUM(movto_info_acrescimo_f(m.grid, 'multa', m.valor)) AS total_multa,
--     SUM(movto_info_acrescimo_f(m.grid, 'juros', m.valor)) AS total_juros,
--     SUM(m.valor + movto_info_acrescimo_f(m.grid, 'multa', m.valor) + movto_info_acrescimo_f(m.grid, 'juros', m.valor)) AS valor_total_aberto
-- FROM movto m
-- LEFT JOIN pessoa p ON m.pessoa = p.grid
-- WHERE m.empresa = $empresa
--   AND m.conta_creditar = '2.1.1'
--   AND (movto_data_baixa_f(m.grid) IS NULL OR movto_data_baixa_f(m.grid) > CURRENT_DATE)
--   AND (m.child = 0 OR m.child IS NULL)
--   AND m.vencto BETWEEN $dt_periodo_ini AND $dt_periodo_fim
-- GROUP BY p.codigo, p.nome, p.cpf
-- ORDER BY cliente;


-- ------------------------------------------------------------------------------
-- OPÇÃO I4: CONTAS A PAGAR EM ABERTO - DETALHADO POR CLIENTE / PESSOA E DOCUMENTO (DESATIVADO)
-- (Lista cada título em aberto individualmente com data de emissão, vencimento, juros, multa e valor total)
-- ------------------------------------------------------------------------------
-- SELECT 
--     p.codigo AS codigo_cliente,
--     COALESCE(p.nome, 'PESSOA NAO IDENTIFICADA') AS cliente,
--     p.cpf AS cnpj_cpf,
--     m.documento AS numero_documento,
--     m.data_doc AS data_emissao,
--     m.vencto AS data_vencimento,
--     mm.nome AS motivo,
--     m.valor AS valor_principal,
--     movto_info_acrescimo_f(m.grid, 'multa', m.valor) AS multa,
--     movto_info_acrescimo_f(m.grid, 'juros', m.valor) AS juros,
--     (m.valor + movto_info_acrescimo_f(m.grid, 'multa', m.valor) + movto_info_acrescimo_f(m.grid, 'juros', m.valor)) AS valor_total_aberto,
--     COALESCE(ma.nome, 'SEM MARCADOR') AS marcador,
--     m.obs
-- FROM movto m
-- LEFT JOIN pessoa p ON m.pessoa = p.grid
-- LEFT JOIN motivo_movto mm ON m.motivo = mm.grid
-- LEFT JOIN marcador ma ON m.marcador = ma.grid
-- WHERE m.empresa = $empresa
--   AND m.conta_creditar = '2.1.1'
--   AND (movto_data_baixa_f(m.grid) IS NULL OR movto_data_baixa_f(m.grid) > CURRENT_DATE)
--   AND (m.child = 0 OR m.child IS NULL)
--   AND m.vencto BETWEEN $dt_periodo_ini AND $dt_periodo_fim
-- ORDER BY cliente, m.vencto, m.grid;


-- ------------------------------------------------------------------------------
-- OPÇÃO J: CONTAS A RECEBER - RESUMO TOTALIZADO POR CATEGORIA E CLIENTE (Ativo 1.3.x)
-- (Soma individualmente por Cliente e agrupa os sem cliente como DEMAIS)
-- ------------------------------------------------------------------------------
SELECT 
    c.codigo AS codigo_conta,
    c.nome AS categoria_conta,
    COALESCE(CAST(p.codigo AS varchar), '-') AS codigo_cliente,
    COALESCE(p.nome, 'DEMAIS (CARTÕES / PIX / SEM CLIENTE VINCULADO)') AS cliente,
    COUNT(m.grid) AS qtd_lancamentos,
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
ORDER BY c.codigo, cliente;



-- ------------------------------------------------------------------------------
-- OPÇÃO K: EXTRATO DETALHADO DE LANÇAMENTOS - CAIXA ADM E BANCOS DA EMPRESA
-- (Exclui Caixas de Pista/PDV "FF x - CAIXA xx", trazendo apenas Caixa ADM e Bancos)
-- ------------------------------------------------------------------------------
SELECT 
    m.data,
    m.hora,
    c.codigo AS codigo_conta,
    c.nome AS conta_financeira,
    mm.nome AS categoria_motivo,
    COALESCE(p.nome, 'NAO ESPECIFICADO') AS pessoa_historico,
    m.documento AS numero_documento,
    CASE 
        WHEN m.conta_debitar = c.codigo THEN 'ENTRADA'
        ELSE 'SAIDA'
    END AS tipo_movimento,
    CASE WHEN m.conta_debitar  = c.codigo THEN m.valor ELSE 0 END AS valor_entrada,
    CASE WHEN m.conta_creditar = c.codigo THEN m.valor ELSE 0 END AS valor_saida,
    m.obs
FROM movto m
JOIN conta c ON (
    (m.conta_debitar = c.codigo OR m.conta_creditar = c.codigo)
    AND (
        (c.codigo LIKE '1.1%' AND UPPER(c.nome) LIKE '%ADM%') 
        OR 
        c.codigo LIKE '1.2%'
    )
)
JOIN motivo_movto mm ON m.motivo = mm.grid
LEFT JOIN pessoa p ON m.pessoa = p.grid
WHERE m.empresa = $empresa
  AND m.data BETWEEN $dt_periodo_ini AND $dt_periodo_fim
ORDER BY c.codigo, m.data, m.hora;


-- ------------------------------------------------------------------------------
-- OPÇÃO L: RESUMO TOTALIZADO POR CATEGORIA/MOTIVO - CAIXA ADM E BANCOS DA EMPRESA
-- (Agrupa Depósitos, Transferências etc., trazendo apenas Caixa ADM e Bancos)
-- ------------------------------------------------------------------------------
SELECT 
    c.codigo AS codigo_conta,
    c.nome AS conta_financeira,
    mm.nome AS categoria_motivo,
    COUNT(m.grid) AS qtd_lancamentos,
    SUM(CASE WHEN m.conta_debitar  = c.codigo THEN m.valor ELSE 0 END) AS total_entradas,
    SUM(CASE WHEN m.conta_creditar = c.codigo THEN m.valor ELSE 0 END) AS total_saidas,
    (SUM(CASE WHEN m.conta_debitar  = c.codigo THEN m.valor ELSE 0 END) - 
     SUM(CASE WHEN m.conta_creditar = c.codigo THEN m.valor ELSE 0 END)) AS saldo_liquido_periodo
FROM movto m
JOIN conta c ON (m.conta_debitar = c.codigo OR m.conta_creditar = c.codigo) 
  AND (
      (c.codigo LIKE '1.1%' AND UPPER(c.nome) LIKE '%ADM%') 
      OR 
      c.codigo LIKE '1.2%'
  )
JOIN motivo_movto mm ON m.motivo = mm.grid
WHERE m.empresa = $empresa
  AND m.data BETWEEN $dt_periodo_ini AND $dt_periodo_fim
GROUP BY c.codigo, c.nome, mm.nome
ORDER BY c.codigo, total_entradas DESC, total_saidas DESC;



-- ------------------------------------------------------------------------------
-- OPÇÃO M: MOVIMENTAÇÃO DE COMBUSTÍVEIS (PARAMETRIZAÇÃO AUTOSYSTEM - POR PERÍODO)
-- ------------------------------------------------------------------------------
WITH medicao_inicial_sub AS (
    -- Busca a última medição física ('M') por depósito registrada ANTES do início do período ($dt_periodo_ini)
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
    -- Consolida a Litragem Inicial por combustível (soma das medições/estoque inicial dos tanques)
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
    -- Movimentações no período ($dt_periodo_ini a $dt_periodo_fim) utilizando as operações nativas do Autosystem
    SELECT 
        l.produto,
        -- Somatório de todas as Entradas (Operações nativas do Autosystem: E, S, TE, DC, O)
        SUM(CASE WHEN l.operacao IN ('E', 'S', 'TE', 'DC', 'O') THEN l.quantidade ELSE 0 END) AS entrada,
        -- Total do Saída Bombas / Venda (Operações nativas do Autosystem: V, C, P, DF, TS, B)
        SUM(CASE WHEN l.operacao IN ('V', 'C', 'P', 'DF', 'TS', 'B') THEN l.quantidade ELSE 0 END) AS venda,
        -- Somatório de Aferição
        SUM(CASE WHEN l.operacao = 'A' THEN l.quantidade ELSE 0 END) AS afericao,
        -- Outras movimentações de estoque
        SUM(CASE WHEN l.operacao IN ('T', 'D') THEN l.quantidade ELSE 0 END) AS outros
    FROM lancto l
    WHERE l.empresa = $empresa
      AND l.data BETWEEN $dt_periodo_ini AND $dt_periodo_fim
    GROUP BY l.produto
),
medicao_final_sub AS (
    -- Busca a última medição física ('M') por depósito registrada até a data final do período ($dt_periodo_fim)
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
    -- Consolida a última medição física registrada por combustível (soma dos tanques)
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


-- ------------------------------------------------------------------------------
-- OPÇÃO N: CONTAS A PAGAR EM ABERTO - RESUMO CONSOLIDADO AGRUPADO POR CLIENTE / PESSOA
-- (Filtra títulos de Contas a Pagar '2.1.1' ainda não baixados no período, calculando juros/multa)
-- ------------------------------------------------------------------------------
SELECT 
    p.codigo AS codigo_cliente,
    COALESCE(p.nome, 'PESSOA NAO IDENTIFICADA') AS cliente,
    p.cpf AS cnpj_cpf,
    COUNT(m.grid) AS qtd_titulos,
    SUM(m.valor) AS valor_principal,
    SUM(movto_info_acrescimo_f(m.grid, 'multa', m.valor)) AS total_multa,
    SUM(movto_info_acrescimo_f(m.grid, 'juros', m.valor)) AS total_juros,
    SUM(m.valor + movto_info_acrescimo_f(m.grid, 'multa', m.valor) + movto_info_acrescimo_f(m.grid, 'juros', m.valor)) AS valor_total_aberto
FROM movto m
LEFT JOIN pessoa p ON m.pessoa = p.grid
WHERE m.empresa = $empresa
  AND m.conta_creditar = '2.1.1'
  AND (movto_data_baixa_f(m.grid) IS NULL OR movto_data_baixa_f(m.grid) > CURRENT_DATE)
  AND (m.child = 0 OR m.child IS NULL)
  AND m.vencto BETWEEN $dt_periodo_ini AND $dt_periodo_fim
GROUP BY p.codigo, p.nome, p.cpf
ORDER BY cliente;


-- ------------------------------------------------------------------------------
-- OPÇÃO O: CONTAS A PAGAR EM ABERTO - DETALHADO POR CLIENTE / PESSOA E DOCUMENTO
-- (Lista cada título em aberto individualmente com data de emissão, vencimento, juros, multa e valor total)
-- ------------------------------------------------------------------------------
SELECT 
    p.codigo AS codigo_cliente,
    COALESCE(p.nome, 'PESSOA NAO IDENTIFICADA') AS cliente,
    p.cpf AS cnpj_cpf,
    m.documento AS numero_documento,
    m.data_doc AS data_emissao,
    m.vencto AS data_vencimento,
    mm.nome AS motivo,
    m.valor AS valor_principal,
    movto_info_acrescimo_f(m.grid, 'multa', m.valor) AS multa,
    movto_info_acrescimo_f(m.grid, 'juros', m.valor) AS juros,
    (m.valor + movto_info_acrescimo_f(m.grid, 'multa', m.valor) + movto_info_acrescimo_f(m.grid, 'juros', m.valor)) AS valor_total_aberto,
    COALESCE(ma.nome, 'SEM MARCADOR') AS marcador,
    m.obs
FROM movto m
LEFT JOIN pessoa p ON m.pessoa = p.grid
LEFT JOIN motivo_movto mm ON m.motivo = mm.grid
LEFT JOIN marcador ma ON m.marcador = ma.grid
WHERE m.empresa = $empresa
  AND m.conta_creditar = '2.1.1'
  AND (movto_data_baixa_f(m.grid) IS NULL OR movto_data_baixa_f(m.grid) > CURRENT_DATE)
  AND (m.child = 0 OR m.child IS NULL)
  AND m.vencto BETWEEN $dt_periodo_ini AND $dt_periodo_fim
ORDER BY cliente, m.vencto, m.grid;