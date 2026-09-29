-- Tabela fato de Sessões, responsável por armazenar as sessões dos usuários dentro da plataforma, neste caso, é uma carga incremental
-- que possui como estratégia incremental um APPEND, pois de acordo com os Stakeholders e até mesmo sistematicamente, não é possível
-- realizar alterações dos dados de reserva, eles apenas acrescentam mais e mais linhas para reservas diferentes, por isso o APPEND,
-- ou seja, APPEND pois se mantém e os dados já existentes referente a reservas são imutáveis, devido a isso, o incremento é pelo
-- id da sessão
{{ config(
    materialized='incremental',
    unique_key='id_sessao',
    incremental_strategy='append',
    on_schema_change='fail'    
) }}

-- Consulta principal que é encarregada por auxiliar na construção da fato
WITH temp_int_sessoes AS (
    SELECT *
    FROM {{ ref('int_sessoes_enriquecidas') }}
    WHERE 1 = 1

        -- Só entrará reservas que não foram canceladas de acordo com stakeholders para fins de mensuração de resultado
        AND flg_sessao_anonima = FALSE

        -- Realiza carga incremental baseando-se diretamente no horário de reserva
        {% if is_incremental() %}
            -- Garante que sempre entrará novos IDs porque se trata de uma Fato Transacional, que sempre será id serve único
            AND NOT EXISTS (SELECT 1 FROM  {{ this }} t WHERE t.id_sessao = id_sessao)
        {% endif %}
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

temp_dim_junk_origem AS (
    SELECT *
    FROM {{ ref('dim_origem_campanha') }}
),

-- Consulta para garantir deduplicação explícita antes da gravação no lote incremental
temp_dedup_sessoes AS (
    SELECT DISTINCT *
    FROM temp_int_sessoes
)

-- Construção da tabela Fato em definitivo
SELECT r.sk_sessao,
       u.sk_usuario,
       d.sk_data AS sk_data_inicio_sessao,
       dr.sk_data AS sk_data_final_sessao,
       j.sk_origem_campanha,

       -- Os campos abaixo, se trata de dimensões do tipo degeneradas que precisam estar presentes para fins de análise
       r.id_sessao,
       CAST(r.dt_hora_inicio AS TIME) AS hr_inicial_sessao, -- A hora virou degenerada para evitar criar uma dimensão somente para hora e deixar a base ainda mais populosa
       CAST(r.dt_hora_fim AS TIME) AS hr_final_sessao, -- A hora virou degenerada mesmo caso acima
       r.flg_houve_clique,
       r.flg_volume_busca_anormal,

       -- Abaixo as métricas que foram solicitadas pelos stakeholers para fins de análise de mensuração e resultados com base nas reservas
       r.qt_duracao_sessao_minutos,
       r.qt_paginas_vistas,
       r.qt_total_buscas,
       r.vlr_menor_preco_pesquisado
FROM temp_dedup_sessoes r
    LEFT JOIN temp_dim_usuario u ON r.id_usuario = u.id_usuario
    LEFT JOIN temp_dim_data d ON CAST(r.dt_hora_inicio AS DATE) = d.dt_registro -- Junção principal de tempo com a questão da de início da sessão
    LEFT JOIN temp_dim_data dr ON CAST(r.dt_hora_fim AS DATE) = dr.dt_registro -- Junção para alimentar SK de data final
    LEFT JOIN temp_dim_junk_origem j ON r.des_canal_aquisicao = j.des_canal_aquisicao
        AND r.des_utm_origem = j.des_utm_origem
        AND r.des_utm_campanha = j.des_utm_campanha
        AND r.tp_dispositivo = j.tp_dispositivo
        AND r.des_pais_operacao = j.des_pais_operacao
WHERE r.id_sessa        
       