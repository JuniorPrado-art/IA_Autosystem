# Projeto IA Autosystem - Relatórios Financeiros (PostgreSQL)

Este repositório contém os scripts SQL, documentação de apoio e mapeamento contábil do sistema **Autosystem** para a geração do relatório de **Fechamento do Movimento Diário** por período e dos módulos de **Contas a Pagar** e **Contas a Receber**.

---

## 📂 Estrutura de Arquivos Criados

| Arquivo | Descrição |
|---|---|
| [`fechamento_autosystem.xml`](file:///d:/Milton%20Junior/Documents/IA_Autosystem/fechamento_autosystem.xml) | **Arquivo XML Final Parametrizado** com a coleção completa dos 12 Datasets SQL do Autosystem. |
| [`fechamento_por_periodo.sql`](file:///d:/Milton%20Junior/Documents/IA_Autosystem/fechamento_por_periodo.sql) | Consultas SQL puras parametrizadas (`:empresa`, `:data_ini`, `:data_fim`) para o relatório de Fechamento Diário. |
| [`contas_pagar_receber_saldo.sql`](file:///d:/Milton%20Junior/Documents/IA_Autosystem/contas_pagar_receber_saldo.sql) | Queries validadas para cálculo exato de saldo em aberto por Fornecedor (Passivo `2.1.1`) e Cliente/Forma (Ativo `1.3.x`). |
| [`investigacao_operacoes_lancto.sql`](file:///d:/Milton%20Junior/Documents/IA_Autosystem/investigacao_operacoes_lancto.sql) | Script de investigação para os tipos de operação (`'E'`, `'M'`, `'V'`), auditoria de bicos e leitura de `bico_encerrante`/`lmc`. |

---

## 🔑 Regras de Negócio & Aprendizados Fundamentais

1. **Livro-Razão Contábil de Partidas Dobradas:**
   - **`lancto`** = item físico da venda.
   - **`movto`** = lançamento contábil/financeiro.
   - **`lancto.mlid = movto.mlid`** = Chave de junção entre o físico e o financeiro.

2. **Cálculo de Saldo em Aberto:**
   - **Contas a Pagar (`2.1.1` - PASSIVO):** `SUM(Crédito) - SUM(Débito)`
   - **Contas a Receber (`1.3.x` - ATIVO):** `SUM(Débito) - SUM(Crédito)`

3. **Filtro de Motivos:**
   - **SEMPRE** utilizar o JOIN em `motivo_movto.nome`. **NUNCA** hardcodar `codigo` ou `grid`.

4. **Operações em `lancto`:**
   - **`V`**: Venda normal (Combustíveis, Produtos e Serviços).
   - **`E`**: Entradas / Trocas / Devoluções / Ajustes.
   - **`M`**: Movimentação Interna / Manual.

5. **Auditoria de Bicos e Encerrantes:**
   - O encerrante inicial e final de cada bico no período é obtido através do `MIN(l.encerrante)` e `MAX(l.encerrante)` filtrado por `operacao = 'V'` e grupo `COMBUSTIVEL`.
   - Como fallback/conferência técnica, a tabela `bico_encerrante` registra os pulsos do concentrador e a tabela `lmc_venda` registra os dados oficiais do LMC.

6. **Tabelas Descartadas (Vazias nesta instalação):**
   - `cupom`, `cupom_produto`, `cupom_total`, `abastecimento`, `lancto_caixa_cancelamento`.

---

## 🚀 Como Utilizar o XML de Consultas (`fechamento_autosystem.xml`)

O arquivo XML disponibilizado contém 12 Datasets parametrizados:
1. `recebimentos_por_forma`: Recebimentos agregados por forma de pagamento (`motivo_movto`).
2. `resumo_vendas_macro`: Totais macro de Combustíveis vs. Produtos/Serviços.
3. `vendas_combustivel_produto`: Detalhamento de volume (L) e valor por combustível.
4. `vendas_combustivel_bico`: Detalhamento de vendas por bico com encerrantes.
5. `vendas_conveniencia_categoria`: Vendas da loja/conveniência por grupo de produto.
6. `sangrias_e_suprimentos`: Registro de sangrias por caixa e turno.
7. `diferencas_caixa`: Apuração de faltas e sobras por operador.
8. `vendas_prazo_clientes`: Vendas faturadas a prazo por cliente (Conta `1.3.03`).
9. `contas_pagar_saldo`: Saldo em aberto por fornecedor (Conta `2.1.1`).
10. `contas_receber_saldo`: Saldo em aberto por cliente e forma/conta (Contas `1.3.x`).
11. `contas_receber_resumo`: Resumo gerencial de contas a receber por tipo de conta.
12. `leitura_bico_encerrante`: Reconciliação de encerrantes e bicos.

**Parâmetros de Entrada:**
- `:empresa` -> Código GRID da filial/empresa.
- `:data_ini` -> Data inicial em formato YYYY-MM-DD.
- `:data_fim` -> Data final em formato YYYY-MM-DD.

