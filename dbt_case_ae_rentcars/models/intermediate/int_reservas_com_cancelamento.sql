-- O objetivo dessa intermediate é unificar as reservas com os seus respetivos eventos de cancelamento.
-- Regras de Negócio:
--      Consolida a reserva com os dados de reembolso/cancelamento (caso existam).
--      Calcula o tempo de duração da locação (em dias): dt_devolucao - dt_retirada.
--      Cria a flag flg_cancelada (TRUE/FALSE).
--      Calcula o Valor Líquido Retido (Valor Total da Reserva - Valor Reembolsado).

-- Consulta temporária com objetivo de aplicar as regras de negócio que estão descritas nos documentos
-- além disso, aplica-se a regra combinado com o Stakeholder onde, uma reserva só pode ser considerada verdadeira
-- caso o campo do usuário ESTEJA PREENCHIDO.
WITH temp_reservas AS (
    SELECT * 
    FROM {{ ref('stg_reservas') }}
    WHERE dt_devolucao >= dt_retirada
        AND id_usuario IS NOT NULL
),

-- Consulta que trás as informações de cancelamento que servira como base de junção com reservas
temp_cancelamentos AS (
    SELECT *
    FROM {{ ref('stg_cancelamentos') }}
),

-- Consulta auxiliar, responsável por construir uma temporária com intuito de trazer números de reservas
-- por usuário, para verificar possíveis fraudes, que de acordo com o Stakeholder, caso tiver mais de uma
-- reserva para o mesmo usuário na mesma data e hora, é sinalização de fraude
temp_fraude_usuario AS (
    SELECT
        id_usuario,
        CAST(dt_hora_reserva AS DATE) AS dt_reserva,
        COUNT(DISTINCT id_reserva) AS qt_reservas_dia
    FROM temp_reservas
    GROUP BY id_usuario,
             CAST(dt_hora_reserva AS DATE)
    HAVING COUNT(DISTINCT id_reserva) > 1 -- Stakeholder definiu que é + de 1 reserva já é suspeita de fraude
)

-- Consulta que possui os campos de reservas e cancelamento, ou seja, enriquece as informações de cancelamento
-- com as informações de reservas.
SELECT *
FROM (
    SELECT {{ dbt_utils.generate_surrogate_key(['r.id_reserva']) }} AS sk_reserva, -- Surrogate key gerada com o package do dbt_utils
            r.id_reserva,
            r.id_sessao,
            r.id_usuario,
            r.id_parceiro,
            r.dt_hora_reserva,
            r.dt_retirada,
            r.dt_devolucao,

            -- Campo criado para identificar a quantidade de dias de locação
            DATEDIFF('day', r.dt_retirada, r.dt_devolucao) AS qt_dias_locacao,
            
            r.des_local_retirada,
            r.des_categoria_veiculo,
            r.vlr_diaria,
            r.vlr_total_reserva,
            r.cod_moeda,
            r.tp_status_reserva,
            r.des_forma_pagamento,
            r.flg_valor_acima_media,

            -- Flag criada que verifica se é possível fraude ou não, baseado na consulta auxiliar anteior
            CASE
                WHEN f.qt_reservas_dia IS NOT NULL THEN TRUE
                ELSE false
            END AS flg_suspeita_fraude_usuario,

            -- Verifica com base no id_cancelamento, se a reserva foi ou não cancelada
            CASE
                WHEN c.id_cancelamento IS NOT NULL THEN TRUE 
                ELSE false
            END AS flg_cancelada,

            c.id_cancelamento,
            c.dt_hora_cancelamento,
            c.des_motivo_cancelamento,
            c.des_responsavel_cancelamento,

            -- Regra aplicada combinada com stakeholder, onde o valor do reembolso quando não declarado, deve se assumir o valor total da reserva
            LEAST(COALESCE(c.vlr_reembolsado, 0.00), r.vlr_total_reserva) AS vlr_reembolsado_valido,

            c.tp_status_reembolso,
            c.flg_cancelamento_sem_reembolso,
            COALESCE(c.qt_dias_antecedencia_retirada, 0) AS qt_dias_antecedencia_retirada,
            c.flg_cancelamento_tardio,

            -- Valor da receita liquida
            r.vlr_total_reserva - LEAST(COALESCE(c.vlr_reembolsado, 0.00), r.vlr_total_reserva) AS vlr_receita_liquida_reserva
    FROM temp_reservas r
        LEFT JOIN temp_cancelamentos c ON r.id_reserva = c.id_reserva
        LEFT JOIN temp_fraude_usuario f ON r.id_usuario = f.id_usuario
            AND CAST(r.dt_hora_reserva AS DATE) = f.dt_reserva
)
-- Regras que buscam normalizar as análises para considerar somente o que de fato é preenchido
-- passado pelos stakeholders
WHERE id_usuario IS NOT NULL 
    AND id_parceiro IS NOT NULL