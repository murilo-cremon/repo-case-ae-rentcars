-- Configurações iniciais, toda nova rodada de execução dessa dimensão, ela será persistida em uma tabela
-- e se trata de uma JUNK DIMENSION, que é referente a armazenar as informações e dados que precisam ser analisados
-- mas que não se encaixam em nenhuma outra dimensão
{{ config(
    materialized='table'
) }}

-- Consulta que busca os dados que caracterizam o motivo do cancelamento da reserva com o objetivo de criar um JUNK DIMENSION para popular as informações
-- que descrevem ainda mais a reserva e o fato em si, o objetivo da junk dimension é incluir campos que não fazem parte de outras
-- dimensões mas que precisam estar presentes nas análises. Isso é uma solicitação direta dos stakeholders que gostariam de 
-- visualizar as informações por esses campos abaixos. Neste caso busca somente onde reservas foram canceladas
WITH temp_dim_junk_reservas AS (
    SELECT DISTINCT 
           tp_status_reembolso,
           des_responsavel_cancelamento,
           des_motivo_cancelamento
    FROM {{ ref('int_reservas_com_cancelamento') }}
    WHERE flg_cancelada = TRUE
)

-- Geração da surrogate key e reorganização dos campos
SELECT {{ dbt_utils.generate_surrogate_key(['tp_status_reembolso', 'des_responsavel_cancelamento', 'des_motivo_cancelamento']) }} AS sk_motivacao_cancelamento,
       tp_status_reembolso,
       des_responsavel_cancelamento,
       des_motivo_cancelamento
FROM temp_dim_junk_reservas