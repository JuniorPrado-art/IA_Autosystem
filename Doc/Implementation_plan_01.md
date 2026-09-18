# Plano de Implementação: Validação de Tabelas e Construção do Script XML de Consultas (Autosystem)

Este plano descreve as etapas para concluir as investigações nas tabelas do sistema **Autosystem** (PostgreSQL) e consolidar todas as consultas SQL validadas em um arquivo **XML parametrizado**, pronto para ser integrado a geradores de relatórios e sistemas de IA.

---

## 🎯 Objetivos

1. **Finalizar a Investigação de Tabelas:**
   - Consolidar as validações para as operações pendentes em `lancto` (`'E'` - Entrada/Troca/Ajuste e `'M'` - Movimento Interno/Manual).
   - Definir o fallback de encerrantes (`bico_encerrante` x `lmc` x `lancto.encerrante`).
2. **Construir o Arquivo XML de Consultas SQL (`fechamento_autosystem.xml`):**
   - Criar uma estrutura XML parametrizada (`:empresa`, `:data_ini`, `:data_fim`) contendo todas as seções do Fechamento Diário, Contas a Pagar e Contas a Receber.
3. **Atualizar a Documentação (`README.md`):**
   - Registrar a nova estrutura de arquivos XML e instruir sobre a execução dos relatórios.

---

## 💡 User Review Required

> [!IMPORTANT]
> **Estrutura do XML**: O arquivo XML será organizado por `dataset` com marcação limpa de parâmetros e consultas SQL prontas para execução em motores de relatório (ex: Jasper, FastReport, Python/Node XML parsers). Se houver alguma especificação ou esquema XML pré-existente (tags específicas), por favor nos informe!

---

## Proposed Changes

### Componente 1: Script de Investigação e Validação de Tabelas

#### [MODIFY] [`investigacao_operacoes_lancto.sql`](file:///d:/Milton%20Junior/Documents/IA_Autosystem/investigacao_operacoes_lancto.sql)
- Complementar as queries de validação incluindo verificação de redundância entre `bico_encerrante`, `lmc` e `lancto`.

---

### Componente 2: Arquivo XML de Consultas Parametrizadas

#### [NEW] [`fechamento_autosystem.xml`](file:///d:/Milton%20Junior/Documents/IA_Autosystem/fechamento_autosystem.xml)
- Criar a estrutura XML completa consolidando os datasets:
  1. `RecebimentosPorForma`: Consolidação de recebimentos por `motivo_movto` (`forma_pgto = true`).
  2. `ResumoVendasMacro`: Combustíveis vs. Produtos/Serviços.
  3. `VendasCombustivelProduto`: Volume em litros, preço médio e total por combustível.
  4. `VendasCombustivelBico`: Detalhamento por bico com encerrante inicial/final.
  5. `VendasConvenienciaCategoria`: Vendas de loja/conveniência por grupo de produto.
  6. `SangriasESuprimentos`: Movimentos de sangria por caixa e turno.
  7. `DiferencasCaixa`: Faltas e sobras de caixa por operador.
  8. `VendasPrazoClientes`: Detalhamento de notas a prazo por cliente (Conta `1.3.03`).
  9. `ContasPagarSaldo`: Saldo em aberto por Fornecedor (Conta `2.1.1` - Passivo).
  10. `ContasReceberSaldo`: Saldo em aberto por Conta de Recebíveis e Cliente (Contas `1.3.x` - Ativo).
  11. `LeituraEncerrantes`: Consulta unificada em `bico_encerrante` / `lmc` para auditoria de bicos.

---

### Componente 3: Documentação do Projeto

#### [MODIFY] [`README.md`](file:///d:/Milton%20Junior/Documents/IA_Autosystem/README.md)
- Atualizar a tabela de arquivos com o arquivo XML criado.
- Registrar o roteiro concluído de validações.

---

## 🧪 Plano de Verificação

### Teste e Validação Estrutural
- Validar a sintaxe do arquivo XML gerado via parser de validação (ex: python `xml.etree.ElementTree`).
- Garantir que todos os parâmetros (`:empresa`, `:data_ini`, `:data_fim`) estejam aplicados de forma consistente em todas as queries.
