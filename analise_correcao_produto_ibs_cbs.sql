-- ==============================================================================
-- PROJETO IA AUTOSYSTEM - ANÁLISE E CORREÇÃO DE CADASTRO IBS/CBS EM PRODUTOS
-- Arquivo: analise_correcao_produto_ibs_cbs.sql
-- Baseado no schema.sql oficial do PostgreSQL (Autosystem / Linx)
--
-- Estrutura Técnica Identificada no schema.sql:
--   1. public.produto (grid bigint NOT NULL PK, codigo text, nome text, codigo_barra text, flag char(1))
--   2. public.produto_ibs_cbs (grid bigint NOT NULL PK, empresa bigint NULL, data_ini date NOT NULL,
--      produto bigint NOT NULL -> FK lógica para produto.grid, cst text NOT NULL,
--      classificacao text NOT NULL, aliquota_ibs_mun float8, aliquota_cbs float8,
--      perc_red_ibs_mun float8, perc_red_cbs float8, perc_dif_ibs_mun float8, perc_dif_cbs float8,
--      aliquota_ibs_uf float8, perc_red_ibs_uf float8, perc_dif_ibs_uf float8, uf text, emsys bool)
--   3. Trigger BEFORE INSERT (pgd_insert_produto_ibs_cbs): Gera automaticamente o campo "grid"
--      via pgd_gxid_f(pgd_sid, nextval('pgd_rid_seq')) e grava auditoria em produto_ibs_cbs_flow.
--   4. Trigger AFTER INSERT (produto_ibs_cbs_sync_tg): Sincroniza automaticamente em exchange_sync.
-- ==============================================================================


-- ------------------------------------------------------------------------------
-- 📌 0. PAINEL DE DIAGNÓSTICO GERAL (RESUMO QUANTITATIVO)
-- Visão consolidada da situação atual entre as tabelas produto e produto_ibs_cbs
-- antes e depois da aplicação das correções.
-- ------------------------------------------------------------------------------
SELECT 
    (SELECT COUNT(*) FROM public.produto) AS total_produtos_cadastrados,
    (SELECT COUNT(DISTINCT produto) FROM public.produto_ibs_cbs) AS produtos_com_algum_ibs_cbs,
    (SELECT COUNT(*) 
     FROM public.produto p 
     WHERE NOT EXISTS (SELECT 1 FROM public.produto_ibs_cbs pic WHERE pic.produto = p.grid)
    ) AS analise_1_sem_nenhum_ibs_cbs,
    (SELECT COUNT(DISTINCT pic.produto) 
     FROM public.produto_ibs_cbs pic 
     WHERE NOT EXISTS (
         SELECT 1 FROM public.produto_ibs_cbs g 
         WHERE g.produto = pic.produto 
           AND g.empresa IS NULL 
           AND g.data_ini = '2026-01-24'::date
     )
    ) AS analise_2_ibs_sem_padrao_24_01,
    (SELECT COUNT(DISTINCT pic.produto) 
     FROM public.produto_ibs_cbs pic 
     WHERE pic.empresa IS NULL 
       AND pic.data_ini = '2026-01-24'::date
    ) AS produtos_ja_regularizados_24_01;


-- ------------------------------------------------------------------------------
-- 🟢 1. PRIMEIRA ANÁLISE: PRODUTOS AUSENTES NA TABELA PRODUTO_IBS_CBS
-- Lista grid, codigo, nome e codigo_barra de todos os produtos cadastrados na
-- tabela "produto" que NÃO possuem nenhum registro vinculado em "produto_ibs_cbs".
-- Link utilizado: produto.grid = produto_ibs_cbs.produto
-- ------------------------------------------------------------------------------
SELECT 
    p.grid,
    p.codigo,
    p.nome,
    p.codigo_barra
FROM public.produto p
LEFT JOIN public.produto_ibs_cbs pic ON pic.produto = p.grid
WHERE pic.produto IS NULL
ORDER BY p.grid;


-- ------------------------------------------------------------------------------
-- 🟣 2A. SEGUNDA ANÁLISE (CONSULTA): PRODUTOS EM PRODUTO_IBS_CBS SEM O CADASTRO PADRÃO (EMPRESA EM BRANCO E DATA_INI 24/01)
-- Analisa os produtos que já possuem registro em "produto_ibs_cbs" (vinculados a alguma
-- empresa ou outra data), mas NÃO possuem o melhor cadastro: empresa IS NULL e data_ini = '2026-01-24'.
-- Exibe também os parâmetros fiscais (CST, classificação, alíquotas) que serão replicados.
-- ------------------------------------------------------------------------------
SELECT 
    base.produto AS grid_produto,
    p.codigo,
    p.nome,
    p.codigo_barra,
    base.qtd_vinculos_atuais,
    base.cst AS cst_referencia,
    base.classificacao AS classificacao_referencia,
    base.aliquota_ibs_mun,
    base.aliquota_cbs,
    base.aliquota_ibs_uf,
    base.uf,
    base.emsys
FROM (
    SELECT DISTINCT ON (pic.produto)
        pic.produto,
        COUNT(*) OVER (PARTITION BY pic.produto) AS qtd_vinculos_atuais,
        pic.cst,
        pic.classificacao,
        COALESCE(pic.aliquota_ibs_mun, 0) AS aliquota_ibs_mun,
        COALESCE(pic.aliquota_cbs, 0.9) AS aliquota_cbs,
        COALESCE(pic.aliquota_ibs_uf, 0.1) AS aliquota_ibs_uf,
        COALESCE(pic.uf, 'MS') AS uf,
        COALESCE(pic.emsys, false) AS emsys
    FROM public.produto_ibs_cbs pic
    WHERE NOT EXISTS (
        SELECT 1
        FROM public.produto_ibs_cbs global_rec
        WHERE global_rec.produto = pic.produto
          AND global_rec.empresa IS NULL
          AND global_rec.data_ini = '2026-01-24'::date
    )
    ORDER BY 
        pic.produto,
        (pic.empresa IS NULL) DESC,
        (pic.aliquota_ibs_mun = 0) DESC,
        pic.data_ini DESC,
        pic.grid DESC
) base
LEFT JOIN public.produto p ON p.grid = base.produto
ORDER BY base.produto;


-- ------------------------------------------------------------------------------
-- 🔑 2B. SEGUNDA ANÁLISE (EXECUÇÃO INSERT): INSERIR CADASTRO SEM EMPRESA (24/01) PARA PRODUTOS QUE JÁ ESTÃO NA PRODUTO_IBS_CBS
-- Insere o registro global (empresa = NULL e data_ini = '2026-01-24') para todos os produtos
-- presentes na tabela "produto_ibs_cbs" que ainda não possuem esse cadastro.
-- Aproveita a tributação (CST/Classificação) já existente do próprio produto na tabela
-- e deixa a trigger oficial pgd_insert_produto_ibs_cbs() gerar o novo "grid".
-- ------------------------------------------------------------------------------
INSERT INTO public.produto_ibs_cbs (
    empresa,
    data_ini,
    produto,
    cst,
    classificacao,
    aliquota_ibs_mun,
    aliquota_cbs,
    perc_red_ibs_mun,
    perc_red_cbs,
    perc_dif_ibs_mun,
    perc_dif_cbs,
    aliquota_ibs_uf,
    perc_red_ibs_uf,
    perc_dif_ibs_uf,
    uf,
    emsys
)
SELECT DISTINCT ON (pic.produto)
    NULL::bigint AS empresa,
    '2026-01-24'::date AS data_ini,
    pic.produto,
    pic.cst,
    pic.classificacao,
    COALESCE(pic.aliquota_ibs_mun, 0) AS aliquota_ibs_mun,
    COALESCE(pic.aliquota_cbs, 0.9) AS aliquota_cbs,
    COALESCE(pic.perc_red_ibs_mun, 0) AS perc_red_ibs_mun,
    COALESCE(pic.perc_red_cbs, 0) AS perc_red_cbs,
    COALESCE(pic.perc_dif_ibs_mun, 0) AS perc_dif_ibs_mun,
    COALESCE(pic.perc_dif_cbs, 0) AS perc_dif_cbs,
    COALESCE(pic.aliquota_ibs_uf, 0.1) AS aliquota_ibs_uf,
    COALESCE(pic.perc_red_ibs_uf, 0) AS perc_red_ibs_uf,
    COALESCE(pic.perc_dif_ibs_uf, 0) AS perc_dif_ibs_uf,
    COALESCE(pic.uf, 'MS') AS uf,
    COALESCE(pic.emsys, false) AS emsys
FROM public.produto_ibs_cbs pic
WHERE NOT EXISTS (
    SELECT 1
    FROM public.produto_ibs_cbs existente
    WHERE existente.produto = pic.produto
      AND existente.empresa IS NULL
      AND existente.data_ini = '2026-01-24'::date
)
ORDER BY 
    pic.produto,
    (pic.empresa IS NULL) DESC,
    (pic.aliquota_ibs_mun = 0) DESC,
    pic.data_ini DESC,
    pic.grid DESC
RETURNING grid, empresa, data_ini, produto, cst, classificacao, aliquota_ibs_mun, aliquota_cbs, aliquota_ibs_uf, uf, emsys;


-- ------------------------------------------------------------------------------
-- 🔹 3A. TERCEIRA ANÁLISE (PRÉ-VISUALIZAÇÃO): SIMULAR INSERÇÃO DOS PRODUTOS SEM NENHUM CADASTRO EM PRODUTO_IBS_CBS
-- Pré-visualiza exatamente como ficarão os registros que serão inseridos na "produto_ibs_cbs"
-- para os produtos da Primeira Análise (que não constam na tabela produto_ibs_cbs),
-- já com empresa em branco (NULL), data_ini = '2026-01-24' e o melhor cadastro de IBS/CBS.
-- ------------------------------------------------------------------------------
SELECT 
    NULL::bigint AS empresa,
    '2026-01-24'::date AS data_ini,
    p.grid AS produto,
    p.codigo,
    p.nome,
    p.codigo_barra,
    '000' AS cst,
    '000001' AS classificacao,
    0 AS aliquota_ibs_mun,
    0.9 AS aliquota_cbs,
    0 AS perc_red_ibs_mun,
    0 AS perc_red_cbs,
    0 AS perc_dif_ibs_mun,
    0 AS perc_dif_cbs,
    0.1 AS aliquota_ibs_uf,
    0 AS perc_red_ibs_uf,
    0 AS perc_dif_ibs_uf,
    'MS' AS uf,
    false AS emsys
FROM public.produto p
WHERE NOT EXISTS (
    SELECT 1 
    FROM public.produto_ibs_cbs pic 
    WHERE pic.produto = p.grid
)
ORDER BY p.grid;


-- ------------------------------------------------------------------------------
-- 🔑 3B. TERCEIRA ANÁLISE (EXECUÇÃO INSERT): INSERIR PRODUTOS AUSENTES JÁ COM O MELHOR CADASTRO IBS/CBS (SEM EMPRESA E DATA_INI 24/01)
-- Insere em "produto_ibs_cbs" todos os produtos da tabela "produto" que não possuem
-- cadastro de IBS/CBS, gravando diretamente sem vínculo de empresa (empresa = NULL),
-- data_ini = '2026-01-24', CST '000', Classificação '000001', CBS 0.9, IBS UF 0.1, IBS Mun 0 e UF 'MS'.
-- ------------------------------------------------------------------------------
INSERT INTO public.produto_ibs_cbs (
    empresa,
    data_ini,
    produto,
    cst,
    classificacao,
    aliquota_ibs_mun,
    aliquota_cbs,
    perc_red_ibs_mun,
    perc_red_cbs,
    perc_dif_ibs_mun,
    perc_dif_cbs,
    aliquota_ibs_uf,
    perc_red_ibs_uf,
    perc_dif_ibs_uf,
    uf,
    emsys
)
SELECT 
    NULL::bigint AS empresa,
    '2026-01-24'::date AS data_ini,
    p.grid AS produto,
    '000' AS cst,
    '000001' AS classificacao,
    0 AS aliquota_ibs_mun,
    0.9 AS aliquota_cbs,
    0 AS perc_red_ibs_mun,
    0 AS perc_red_cbs,
    0 AS perc_dif_ibs_mun,
    0 AS perc_dif_cbs,
    0.1 AS aliquota_ibs_uf,
    0 AS perc_red_ibs_uf,
    0 AS perc_dif_ibs_uf,
    'MS' AS uf,
    false AS emsys
FROM public.produto p
WHERE NOT EXISTS (
    SELECT 1 
    FROM public.produto_ibs_cbs pic 
    WHERE pic.produto = p.grid
)
ORDER BY p.grid
RETURNING grid, empresa, data_ini, produto, cst, classificacao, aliquota_ibs_mun, aliquota_cbs, aliquota_ibs_uf, uf, emsys;


-- ------------------------------------------------------------------------------
-- 📌 4. VALIDAÇÃO POR PRODUTO (EXEMPLO CÓDIGO 30 / GRID 10706)
-- Consulta para validar como ficaram os registros na tabela produto_ibs_cbs
-- para um produto específico (como o código '30' - grid 10706 do exemplo).
-- ------------------------------------------------------------------------------
SELECT 
    pic.grid AS grid_ibs_cbs,
    pic.empresa,
    pic.data_ini,
    pic.produto AS grid_produto,
    p.codigo,
    p.nome,
    p.codigo_barra,
    pic.cst,
    pic.classificacao,
    pic.aliquota_ibs_mun,
    pic.aliquota_cbs,
    pic.perc_red_ibs_mun,
    pic.perc_red_cbs,
    pic.perc_dif_ibs_mun,
    pic.perc_dif_cbs,
    pic.aliquota_ibs_uf,
    pic.perc_red_ibs_uf,
    pic.perc_dif_ibs_uf,
    pic.uf,
    pic.emsys
FROM public.produto_ibs_cbs pic
JOIN public.produto p ON p.grid = pic.produto
WHERE p.codigo = '30' OR p.grid = 10706
ORDER BY (pic.empresa IS NULL) DESC, pic.data_ini DESC, pic.grid;

