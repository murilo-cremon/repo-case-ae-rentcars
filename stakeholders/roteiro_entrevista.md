# Roteiro de Entrevista com Stakeholders — Área de Produto

> **Projeto:** Modelagem analítica da plataforma de reservas/locação de veículos (dbt + DuckDB)
> **Área entrevistada:** Produto
> **Responsável pela entrevista:** Murilo — Analytics Engineering
> **Objetivo:** Levantar necessidades de negócio, regras e métricas da área de Produto e convertê-las em requisitos técnicos para a camada de dados (modelos dbt).

---

## 1. Contexto de negócio

A plataforma conecta **usuários** (quem busca e reserva veículos) a **parceiros** (locadoras). O usuário navega, realiza buscas, reserva e, em alguns casos, cancela. A área de **Produto** é responsável por evoluir a experiência da plataforma e precisa responder perguntas como:

- Os usuários estão encontrando o que procuram, ou desistem durante a busca?
- Quais canais de aquisição trazem usuários que **realmente reservam**?
- Onde estamos perdendo receita: na busca, na reserva ou no cancelamento?
- Quais parceiros e categorias de veículo geram mais valor?

### O problema hoje

Hoje as análises de Produto dependem de extrações pontuais e planilhas montadas manualmente. Cada analista aplica regras próprias (o que é uma reserva válida, o que é uma sessão, como tratar cancelamentos), e o resultado é:

1. **Números divergentes** entre relatórios sobre a mesma métrica (ex.: "total de reservas").
2. **Reservas inválidas contaminando a análise** (reservas sem usuário associado ou canceladas entram na conta de receita).
3. **Alto tempo de resposta**: perguntas simples exigem horas de tratamento de dados.
4. **Dificuldade de análise multidimensional**: cruzar usuário × parceiro × data × campanha exige joins complexos sobre tabelas brutas.

### Por que uma modelagem dimensional

Produto precisa olhar o mesmo dado por **vários ângulos** (tempo, usuário, parceiro, campanha, motivo de cancelamento). Por isso o dado foi modelado em **dimensões (`dim_`)**, que descrevem o contexto, e **fatos (`fct_`)**, que registram os eventos mensuráveis. Isso permite responder perguntas novas combinando dimensões, sem reconstruir a lógica a cada análise.

---

## 2. Participantes sugeridos

| Papel | Foco na entrevista |
|---|---|
| Head / Gerente de Produto | Prioridades, metas e decisões que dependem de dados |
| Product Manager (busca e conversão) | Funil, comportamento de busca, abandono |
| Product Manager (marketplace / parceiros) | Performance de parceiros, comissão, categorias |
| Product Analyst | Como acessa dados hoje, dores do dia a dia |
| Designer / UX Researcher | Uso por dispositivo, jornada de sessão |

---

## 3. Roteiro estruturado de perguntas

### Bloco A — Abertura e objetivos (5 min)

1. Quais são as principais metas da área de Produto neste trimestre?
2. Quais decisões vocês tomam hoje que dependem de dados?
3. Se pudessem ter **uma** resposta confiável amanhã, qual seria?

### Bloco B — Reservas e receita

4. O que vocês consideram uma **reserva válida**? Existe alguma situação em que uma reserva não deve entrar na análise?
5. Reservas **canceladas** devem ser consideradas nas métricas de resultado? Em qual momento um cancelamento passa a "descontar" da receita?
6. Como vocês definem **receita líquida** de uma reserva? A comissão do parceiro entra no cálculo?
7. O que caracteriza uma reserva com **valor acima da média**? A média é global, por categoria de veículo ou por parceiro?
8. Como vocês tratam reservas com **suspeita de fraude**? Devem ser excluídas, sinalizadas ou analisadas à parte?
9. Qual a granularidade de análise de tempo mais usada: data da reserva, da retirada ou da devolução?

### Bloco C — Comportamento do usuário (sessões e buscas)

10. Como vocês definem uma **sessão**? Sessões anônimas (sem login) devem entrar nas métricas de comportamento?
11. O que é uma sessão "de qualidade"? Existe um mínimo de duração ou de páginas vistas?
12. O que caracteriza um **volume de busca anormal**? Isso indica problema de produto, bot ou usuário comparando preços?
13. Como medem **engajamento** (buscas por usuário, cliques, tempo em sessão)?
14. Qual a importância da análise por **dispositivo** (mobile, tablet, desktop)? Decisões de design dependem disso?
15. Como identificam o **usuário ativo**? Qual janela de tempo é usada (7, 30, 90 dias)?

### Bloco D — Cancelamentos

16. Quais **motivos de cancelamento** são mais críticos para o produto?
17. Quem pode cancelar (cliente, parceiro, administrador, sistema)? Essa distinção muda a análise?
18. O que é um **cancelamento tardio**? Qual a regra de antecedência em dias?
19. Como acompanham o **status do reembolso** (pendente, negado, processado)? Existe meta de tempo?
20. Cancelamentos sem reembolso são tratados de forma diferente na análise de receita?

### Bloco E — Parceiros e marketplace

21. Quais indicadores definem um **parceiro saudável**?
22. Como funciona a **taxa de comissão** e quando ela é ajustada? Como o ajuste afeta o repasse?
23. Existe segmentação por **categoria comercial (tier)**? Como ela é usada?
24. A análise por **país de operação** é relevante?

### Bloco F — Aquisição e campanhas

25. Como vocês avaliam a **eficiência dos canais de aquisição**? Só volume de usuários ou também reservas e receita?
26. A análise por **UTM (origem e campanha)** é feita hoje? Com que frequência?
27. Precisam ligar a campanha de origem à **primeira reserva** do usuário?

### Bloco G — Acesso a dados e governança

28. Como vocês acessam dados hoje? Quais ferramentas usam?
29. Quanto tempo leva para responder uma pergunta nova de negócio?
30. Já tiveram discrepância entre números de fontes diferentes? Qual foi o impacto?
31. Quais dados são sensíveis (contato de parceiros, dados de usuário) e precisam de cuidado no acesso?
32. Qual a **frequência de atualização** aceitável (diária, horária)?

### Bloco H — Fechamento (5 min)

33. Há alguma métrica ou análise que não perguntamos e é crítica?
34. Quem seria o ponto focal da área para validar os modelos?
35. Como definiríamos o sucesso desta entrega daqui a 90 dias?

---

## 4. Regras de negócio levantadas

> As regras abaixo consolidam o que foi alinhado com Produto e estão implementadas nas camadas `staging` e `intermediate`.

| # | Regra | Onde é aplicada |
|---|---|---|
| RN01 | Somente reservas **com usuário associado** entram na análise de resultado. | `int_reservas_com_cancelamento` / `fct_reservas` |
| RN02 | Reservas **canceladas** ficam fora da fato de reservas, e são analisadas em `fct_cancelamentos`. | `fct_reservas` (`flg_cancelada = FALSE`) |
| RN03 | O valor total da reserva e a diária não podem ser negativos. | Constraints e testes em `fct_reservas` |
| RN04 | Reservas com valor **acima da média** são sinalizadas por flag. | `flg_valor_acima_media` |
| RN05 | Reservas com indício de **fraude** são sinalizadas, não removidas. | `flg_suspeita_fraude_usuario` |
| RN06 | Um cancelamento é **tardio** conforme a antecedência em dias em relação à retirada. | `flg_cancelamento_tardio` |
| RN07 | Cancelamentos sem reembolso são identificados por flag para análise financeira. | `flg_cancelamento_sem_reembolso` |
| RN08 | Volumes anormais de busca em uma sessão são sinalizados. | `flg_volume_busca_anormal` |
| RN09 | A duração e as páginas vistas de uma sessão não podem ser negativas. | Constraints e testes em `fct_sessoes` |
| RN10 | O código de país do parceiro possui 2 caracteres, e o código da moeda possui 3. | Constraints e testes em `dim_parceiros` / `dim_detalhe_reserva` |
| RN11 | E-mail de contato do parceiro deve ter formato válido. | Teste em `dim_parceiros` |
| RN12 | Comissão ajustada é sinalizada, e a taxa ajustada é usada no repasse. | `flg_comissao_ajustada`, `vlr_taxa_comissao_ajustada` |
| RN13 | Toda tabela fato se relaciona às dimensões por **surrogate keys**, com integridade referencial testada. | Testes `relationships` |

---

## 5. Métricas de negócio

### Reservas e receita
| Métrica | Definição | Fonte |
|---|---|---|
| Total de reservas | Contagem de reservas válidas (não canceladas, com usuário) | `fct_reservas` |
| Receita bruta | Soma de `vlr_total_reserva` | `fct_reservas` |
| Receita líquida | Soma de `vlr_receita_liquida_reserva` | `fct_reservas` |
| Ticket médio | Receita bruta ÷ total de reservas | `fct_reservas` |
| Diária média | Média de `vlr_diaria` | `fct_reservas` |
| Duração média da locação | Média de `qt_dias_locacao` | `fct_reservas` |
| % reservas acima da média | Reservas com `flg_valor_acima_media` ÷ total | `fct_reservas` |
| % reservas com suspeita de fraude | Reservas com `flg_suspeita_fraude_usuario` ÷ total | `fct_reservas` |

### Cancelamentos
| Métrica | Definição | Fonte |
|---|---|---|
| Taxa de cancelamento | Cancelamentos ÷ (reservas + cancelamentos) | `fct_cancelamentos` + `fct_reservas` |
| % cancelamento tardio | Cancelamentos com `flg_cancelamento_tardio` ÷ total | `fct_cancelamentos` |
| Valor reembolsado | Soma de `vlr_reembolsado_valido` | `fct_cancelamentos` |
| Antecedência média | Média de `qt_dias_antecedencia_retirada` | `fct_cancelamentos` |
| Cancelamentos por motivo e responsável | Contagem por `dim_motivo_cancelamento` | `fct_cancelamentos` |

### Comportamento e funil
| Métrica | Definição | Fonte |
|---|---|---|
| Sessões | Contagem de sessões | `fct_sessoes` |
| Duração média da sessão | Média de `qt_duracao_sessao_minutos` | `fct_sessoes` |
| Páginas por sessão | Média de `qt_paginas_vistas` | `fct_sessoes` |
| Taxa de clique | Sessões com `flg_houve_clique` ÷ total | `fct_sessoes` |
| Buscas por sessão | Média de `qt_total_buscas` | `fct_sessoes` |
| Menor preço pesquisado médio | Média de `vlr_menor_preco_pesquisado` | `fct_sessoes` |
| Conversão busca → reserva | Usuários com reserva ÷ usuários com busca | `dim_usuarios` |
| Uso por dispositivo | Acessos mobile / tablet / desktop | `dim_usuarios` |

### Parceiros
| Métrica | Definição | Fonte |
|---|---|---|
| Receita líquida por parceiro | Soma de `vlr_total_receita_liquida` | `dim_parceiros` |
| Total transacionado | `vlr_total_transacionado` | `dim_parceiros` |
| Comissão estimada | `vlr_comissao_estimada` | `dim_parceiros` |
| % parceiros com comissão ajustada | Parceiros com `flg_comissao_ajustada` ÷ total | `dim_parceiros` |

---

## 6. Como a área acessa dados hoje vs. como deveria acessar

### Situação atual (AS-IS)

- Extrações manuais do banco transacional, feitas por analistas.
- Planilhas com regras replicadas e sem versionamento.
- Cada pessoa aplica sua própria definição de reserva válida, sessão e cancelamento.
- Sem testes de qualidade: erros só aparecem quando alguém questiona o número.
- Sem documentação central: o conhecimento fica na cabeça de quem construiu o relatório.
- Dependência do time de dados para qualquer pergunta nova.

### Situação desejada (TO-BE)

- Camada analítica única, com **regras de negócio aplicadas uma vez** nos modelos dbt.
- Produto consome as tabelas `dim_` e `fct_` diretamente (SQL, BI ou camada semântica), com **autonomia**.
- **Contratos de dados** (`contract.enforced`) nos marts: colunas e tipos estáveis, com mudança controlada.
- **Testes automatizados** (unicidade, not null, integridade referencial, faixas de valor) rodando a cada execução.
- **Documentação e linhagem** geradas pelo `dbt docs`, com dono, criticidade e SLA definidos em `meta`.
- Métricas padronizadas: um único número para cada indicador.

| Aspecto | Hoje | Depois |
|---|---|---|
| Fonte dos dados | Extração manual / planilhas | Marts dimensionais no dbt |
| Definição de reserva válida | Varia por analista | Única, na `int_reservas_com_cancelamento` |
| Qualidade | Sem verificação | Testes + contratos |
| Documentação | Inexistente ou dispersa | `schema.yml` + `dbt docs` |
| Tempo para responder pergunta nova | Horas / dias | Minutos (SQL sobre dimensões e fatos) |
| Análise multidimensional | Joins complexos sobre dado bruto | Joins simples por surrogate key |

---

## 7. Critérios de sucesso

- 100% dos testes dos marts passando na execução diária.
- Uma única definição publicada para cada métrica da seção 5.
- Produto responde perguntas de rotina sem abrir chamado ao time de dados.
- Redução do tempo de resposta a perguntas novas de horas para minutos.
- Nenhuma quebra de contrato não comunicada nos marts.

---

## 8. Próximos passos

1. Validar este roteiro e as regras (seção 4) com o ponto focal de Produto.
2. Priorizar os itens da seção 7.3.
3. Definir SLA de atualização e canal de comunicação de mudanças de contrato.
4. Publicar a documentação (`dbt docs`) e treinar a área no uso dos marts.

> **Nota:** as respostas e regras acima foram estruturadas a partir do modelo dimensional implementado e das necessidades típicas da área de Produto, e devem ser confirmadas com os stakeholders reais na entrevista.