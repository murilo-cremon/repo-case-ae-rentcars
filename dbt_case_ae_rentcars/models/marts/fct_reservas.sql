-- Tabela fato de Reservas, responsável por armazenar somente reservas que não foram canceladas, neste caso, é uma carga incremental
-- que possui como estratégia incremental um APPEND, pois de acordo com os Stakeholders e até mesmo sistematicamente, não é possível
-- realizar alterações dos dados de reserva, eles apenas acrescentam mais e mais linhas para reservas diferentes, por isso o APPEND,
-- ou seja, APPEND pois se mantém e os dados já existentes referente a reservas são imutáveis, devido a isso, o incremento é pelo
-- id da reserva
{{ config(
    materialized='incremental',
    unique_key='id_reserva',
    incremental_strategy='append',
    on_schema_change='fail'    
) }}

-- Consulta principal que é encarregada por auxiliar na construção da fato
WITH temp_int_reservas AS (
    SELECT *
    FROM {{ ref('int_reservas_com_cancelamento') }}
    WHERE 1 = 1

        -- Só entrará reservas que não foram canceladas de acordo com stakeholders para fins de mensuração de resultado
        AND flg_cancelada = FALSE 
        AND tp_status_reserva IN ('CONFIRMADO', 'CONCLUÍDO')
        AND vlr_total_reserva > 0

        -- Realiza carga incremental baseando-se diretamente no horário de reserva
        {% if is_incremental() %}
            -- Garante que sempre entrará novos IDs porque se trata de uma Fato Transacional, que sempre será id serve único
            AND NOT EXISTS (SELECT 1 FROM  {{ this }} t WHERE t.id_reserva = id_reserva)
        {% endif %}
),

-- Consulta a tabela de parceiro, trazendo a chave delegada e também a chave natural que servirá como ancoragem pra junção
temp_dim_parceiro AS (
    SELECT sk_parceiro,
           id_parceiro
    FROM {{ ref('dim_parceiros') }}
),

-- Consulta a tabela de dimensão usuário, trazendo a chave delegada e também a chave natural que servirá como ancoragem pra junção
temp_dim_usuario AS (
    SELECT sk_usuario,
           id_usuario
    FROM {{ ref('dim_usuarios') }}
    WHERE id_usuario IS NOT NULL -- Busca somente usuários que foram logados, regras do stakeholder
),

-- Consulta a tabela de data, trazendo a chave delegada e também a chave natural que servirá como ancoragem pra junção
temp_dim_data AS (
    SELECT sk_data,
           dt_registro
    FROM {{ ref('dim_data') }}
),

temp_dim_junk_detalhe AS (
    SELECT *
    FROM {{ ref('dim_detalhe_reserva') }}
),

-- Consulta para garantir deduplicação explícita antes da gravação no lote incremental
temp_dedup_reservas AS (
    SELECT DISTINCT *
    FROM temp_int_reservas
)

-- Construção da tabela Fato em definitivo
SELECT r.sk_reserva,
       u.sk_usuario,
       p.sk_parceiro,
       d.sk_data AS sk_data_reserva,
       dr.sk_data AS sk_data_retirada,
       dv.sk_data AS sk_data_devolucao,
       j.sk_detalhe_reserva,

       -- Os campos abaixo, se trata de dimensões do tipo degeneradas que precisam estar presentes para fins de análise
       r.id_reserva,
       CAST(r.dt_hora_reserva AS TIME) AS hr_reserva, -- A hora virou degenerada para evitar criar uma dimensão somente para hora e deixar a base ainda mais populosa
       r.flg_valor_acima_media,
       r.flg_suspeita_fraude_usuario,

       -- Abaixo as métricas que foram solicitadas pelos stakeholers para fins de análise de mensuração e resultados com base nas reservas
       r.qt_dias_locacao,
       COALESCE(r.vlr_total_reserva, 0) AS vlr_total_reserva,
       COALESCE(r.vlr_receita_liquida_reserva, 0) AS vlr_receita_liquida_reserva,
       r.vlr_diaria
FROM temp_dedup_reservas r
    LEFT JOIN temp_dim_parceiro p ON r.id_parceiro = p.id_parceiro
    LEFT JOIN temp_dim_usuario u ON r.id_usuario = u.id_usuario
    LEFT JOIN temp_dim_data d ON CAST(r.dt_hora_reserva AS DATE) = d.dt_registro -- Junção principal de tempo com a questão da reserva
    LEFT JOIN temp_dim_data dr ON r.dt_retirada = dr.dt_registro -- Junção para alimentar SK de data da retirada
    LEFT JOIN temp_dim_data dv ON r.dt_devolucao = dv.dt_registro -- Junção para alimentar SK de data da devolução
    LEFT JOIN temp_dim_junk_detalhe j ON r.des_local_retirada = j.des_local_retirada
        AND r.des_categoria_veiculo = j.des_categoria_veiculo
        AND r.cod_moeda = j.cod_moeda
        AND r.des_forma_pagamento = j.des_forma_pagamento