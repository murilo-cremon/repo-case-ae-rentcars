-- O objetivo dessa intermediate é  agrupar métricas operacionais e financeiras por parceiro/locadora.
-- Regras de Negócio:
--    Consolida total de buscas clicadas vs. total de reservas concluídas por parceiro.
--    Calcula o Taxa de Conversão do Parceiro e a comissão estimada acumulada (vlr_total_reserva * vlr_taxa_comissao).

-- Consulta temporária que trás apenas os parceiros que estão ATIVOS
WITH temp_parceiros AS (
    SELECT * 
    FROM {{ ref('stg_parceiro') }}
    WHERE tp_status_parceiro = 'ATIVO'
),

-- Consulta auxiliar que realiza a agregação de métricas financeiras das reserva, para que sirva de apoio
-- para compor o descritivo quantitativo do parceiro
temp_reservas AS (
    SELECT id_parceiro,
           COUNT(DISTINCT id_reserva) AS qt_total_reservas,
           SUM(vlr_total_reserva) AS vlr_total_transacionado,
           SUM(vlr_receita_liquida_reserva) AS vlr_total_receita_liquida
    FROM {{ ref('int_reservas_com_cancelamento') }}
    GROUP BY id_parceiro
)

-- Consulta final, que constrói as características e informações do parceiro, tentando alcançar maior completude
-- sobre os dados que existentes, e enriquecendo ainda mais conforme os campos neles existentes.
SELECT {{ dbt_utils.generate_surrogate_key(['p.id_parceiro']) }} AS sk_parceiro, -- Surrogate Key geradata via package do dbt_utils
       p.id_parceiro,
       p.nome_parceiro,
       p.cod_pais_operacao,
       p.des_pais_operacao,
       p.des_categoria_comercial,
       p.tp_status_parceiro,
       p.dt_hora_cadastro,
       p.dt_hora_atualizacao,
       p.email_contato,
       p.vlr_taxa_comissao,
       
       -- Aplicação da regra de taxa da comissão, seguindo os critérios de regra
       CASE 
          WHEN p.vlr_taxa_comissao < 0.05 THEN 0.05
          WHEN p.vlr_taxa_comissao > 0.30 THEN 0.30
          ELSE p.vlr_taxa_comissao 
        END AS vlr_taxa_comissao_ajustada,

        -- Valor da comissão estimado, com os ajustes que foram realizados dado a regra juntamente com stakeholders
        ROUND(
            COALESCE(r.vlr_total_receita_liquida, 0.00)
            * 
            CASE 
                WHEN p.vlr_taxa_comissao < 0.05 THEN 0.05
                WHEN p.vlr_taxa_comissao > 0.30 THEN 0.30
                ELSE p.vlr_taxa_comissao 
            END, 
            2
        ) AS vlr_comissao_estimada,
        
        -- Cria-se flag para saber se houve ou não intervenção no ajuste do valor da comissão
        CASE 
          WHEN p.vlr_taxa_comissao < 0.05 THEN TRUE
          WHEN p.vlr_taxa_comissao > 0.30 THEN TRUE
          ELSE FALSE
        END AS flg_comissao_ajustada,

        -- Campos abaixos, representam um quantiativo e valores nominais financeiros para descrição do parceiro
        COALESCE(r.qt_total_reservas, 0) AS qt_total_reservas,
        COALESCE(r.vlr_total_transacionado, 0.00) AS vlr_total_transacionado,
        COALESCE(r.vlr_total_receita_liquida, 0.00) AS vlr_total_receita_liquida,
FROM temp_parceiros p
    LEFT JOIN temp_reservas r ON p.id_parceiro = r.id_parceiro

