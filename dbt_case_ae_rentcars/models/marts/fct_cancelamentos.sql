-- Tabela fato de Reservas, responsável por armazenar somente reservas que não foram canceladas, neste caso, é uma carga incremental
-- que possui como estratégia incremental um APPEND, pois de acordo com os Stakeholders e até mesmo sistematicamente, não é possível
-- realizar alterações dos dados de reserva, eles apenas acrescentam mais e mais linhas para reservas diferentes, por isso o APPEND,
-- ou seja, APPEND pois se mantém e os dados já existentes referente a reservas são imutáveis, devido a isso, o incremento é pelo
-- id da reserva
{{ config(
    materialized='incremental',
    unique_key='id_cancelamento',
    incremental_strategy='append',
    on_schema_change='fail'
) }}

-- Consulta principal que é encarregada por auxiliar na construção da fato
WITH temp_int_cancelamento AS (
    SELECT *
    FROM {{ ref('int_reservas_com_cancelamento') }}
    WHERE 1 = 1

        -- Só entrará reservas que não foram canceladas de acordo com stakeholders para fins de mensuração de resultado
        AND flg_cancelada = TRUE 

        -- Realiza carga incremental baseando-se diretamente no horário de reserva
        {% if is_incremental() %}
            -- Garante que sempre entrará novos IDs porque se trata de uma Fato Transacional, que sempre será neste casa únicos
            AND NOT EXISTS (SELECT 1 FROM  {{ this }} t WHERE t.id_cancelamento = id_cancelamento)
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

temp_dim_junk_motivacao_cancelamento AS (
    SELECT *
    FROM {{ ref('dim_motivacao_cancelamento') }}
),

-- Consulta para garantir deduplicação explícita antes da gravação no lote incremental
temp_dedup_cancelamento AS (
    SELECT DISTINCT *
    FROM temp_int_cancelamento
)

-- Construção da tabela Fato em definitivo
SELECT * FROM (
    SELECT u.sk_usuario,
        p.sk_parceiro,
        d.sk_data AS sk_data_cancelamento,
        j.sk_motivacao_cancelamento,

        -- Os campos abaixo, se trata de dimensões do tipo degeneradas que precisam estar presentes para fins de análise
        r.id_reserva,
        r.id_cancelamento,
        CAST(r.dt_hora_cancelamento AS TIME) AS hr_cancelamento, -- A hora virou degenerada para evitar criar uma dimensão somente para hora e deixar a base ainda mais populosa
        r.flg_cancelamento_tardio,
        r.flg_cancelamento_sem_reembolso,

        -- Abaixo as métricas que foram solicitadas pelos stakeholers para fins de análise de mensuração e resultados com base nas reservas
        r.qt_dias_antecedencia_retirada,
        r.vlr_reembolsado_valido
    FROM temp_dedup_cancelamento r
        LEFT JOIN temp_dim_parceiro p ON r.id_parceiro = p.id_parceiro
        LEFT JOIN temp_dim_usuario u ON r.id_usuario = u.id_usuario
        LEFT JOIN temp_dim_data d ON CAST(r.dt_hora_cancelamento AS DATE) = d.dt_registro -- Junção principal de tempo com a questão do cancelamento
        LEFT JOIN temp_dim_junk_motivacao_cancelamento j ON r.tp_status_reembolso = j.tp_status_reembolso
            AND r.des_responsavel_cancelamento = j.des_responsavel_cancelamento
            AND r.des_motivo_cancelamento = j.des_motivo_cancelamento
)

-- Regra adotada por negócio, para eliminar qualquer ruído que possa vir a ter e evitar que as análises possam ser prejudicadas
WHERE sk_parceiro IS NOT NULL
    AND sk_usuario IS NOT NULL