-- Consulta primária, que realiza a busca de todas as consultas da source, justamente no arquivo _stg_sources.yml
WITH temp_fonte AS (
    SELECT *
    FROM {{ source('raw_rentcars', 'raw_bookings') }}
),

-- Consulta temporária com objetivo de realizar a deduplicação das informações que vem diretamente dos arquivos em raw.
temp_desduplicado AS (
    SELECT *, -- Nesse caso poderia usar distinct, porém, feito com row number para garantir que no mínimo peguemos o registro mais atualizado
        ROW_NUMBER() OVER (
            PARTITION BY booking_id 
            ORDER BY booked_at DESC
        ) AS rank
    FROM temp_fonte
),

-- Consulta temporária responsável por realizar a mudança do data type abaixo, renomear as colunas e realizar operações de
-- padronização dos dados e limpeza, com base no UPPER e TRIM, além disso, garantir a normalização primária das informações
-- que vem dos arquivos raw.
temp_conversao_tipagem_limpeza AS (
    SELECT CAST(booking_id AS varchar)                     AS id_reserva,
           CAST(session_id AS varchar)                     AS id_sessao,
           CAST(user_id AS varchar)                        AS id_usuario,
           CAST(partner_id AS varchar)                     AS id_parceiro,
           CAST(booked_at AS timestamp)                    AS dt_hora_reserva,
           CAST(pickup_date AS date)                       AS dt_retirada,
           CAST(dropoff_date AS date)                      AS dt_devolucao,
           UPPER(TRIM(CAST(pickup_location AS VARCHAR)))   AS des_local_retirada,
           UPPER(TRIM(CAST(car_category AS varchar)))      AS des_categoria_veiculo,
           CAST(daily_rate AS decimal(10,2))               AS vlr_diaria,
           CAST(total_amount AS decimal(10,2))             AS vlr_total_reserva,
           UPPER(TRIM(CAST(currency AS varchar)))          AS cod_moeda,

           -- Realiza o tratamento para normalização das informações que estão persistidas de formas diferentes o mesmo valor, através do UPPER e do TRIM
           UPPER(TRIM(CAST(status AS varchar)))            AS tp_status_reserva,

           UPPER(TRIM(CAST(payment_method AS varchar)))    AS des_forma_pagamento
    FROM temp_desduplicado
    WHERE rank = 1
),

-- Tabela referente que serve como auxílio para geração da flag de identificação de possível valor acima
temp_total_reserva_categoria AS (
    SELECT des_categoria_veiculo,
           AVG(vlr_total_reserva) AS vlr_medio_total_reserva
    FROM temp_conversao_tipagem_limpeza
    GROUP BY des_categoria_veiculo
),

-- As flags que são criadas servem de forma agnóstica e não necessariamente elimina registro, mas sim, enriquecem as
-- informações para possíveis tratamentos, análises e demais variações
temp_tratamento_enriquecimento AS (
    SELECT id_reserva,
           id_sessao,
           id_usuario,
           id_parceiro,
           dt_hora_reserva,
           dt_retirada,
           dt_devolucao,
           
           -- Realizada tratamento de nulificação preenchendo o valor NAO INFORMADO em caso de valor nulo
           COALESCE(des_local_retirada, 'NÃO INFORMADO') AS des_local_retirada,

           -- Realizada tratamento de nulificação preenchendo o valor NAO INFORMADO em caso de valor nulo
           COALESCE(des_categoria_veiculo, 'NÃO INFORMADO') AS des_categoria_veiculo,

           vlr_diaria,

           -- Trata os valores nulos como zero
           COALESCE(vlr_total_reserva, 0) AS vlr_total_reserva,

           cod_moeda,

           -- Conversão dos status em inglês para português para que possa em outras camadas futuras servir negócio
           CASE
              WHEN tp_status_reserva = 'CONFIRMED' THEN 'CONFIRMADO'
              WHEN tp_status_reserva = 'PENDING' THEN 'PENDENTE'
              WHEN tp_status_reserva = 'COMPLETED' THEN 'CONCLUÍDO'
              WHEN tp_status_reserva = 'CANCELLED' THEN 'CANCELADO'
              ELSE 'NÃO COMPARECIMENTO'
            END AS tp_status_reserva,

            -- Transforma a forma de pagamento de Débito e Crédito em um modo mais amigável para fins de consumo
            CASE
              WHEN des_forma_pagamento IS NULL THEN 'NÃO INFORMADO'
              WHEN des_forma_pagamento = 'CREDIT_CARD' THEN 'CARTÃO DE CRÉDITO'
              WHEN des_forma_pagamento = 'DEBIT_CARD' THEN 'CARTÃO DE DÉBITO'
              ELSE des_forma_pagamento
            END AS des_forma_pagamento,

            -- De acordo com o dicionário, valores que estão acima do padrão, devem ser investigados, por isso a criação dessa flag
            -- pois possibilita ter uma visão dos registros que estão com essa flag = TRUE. Essa solicitação vem diretamente
            -- do dicionário de dados   
            CASE
                WHEN vlr_total_reserva > (SELECT MAX(vlr_medio_total_reserva)
                                          FROM temp_total_reserva_categoria ttr
                                          WHERE ttr.des_categoria_veiculo = des_categoria_veiculo) THEN TRUE
                ELSE FALSE
            END AS flg_valor_acima_media
    FROM temp_conversao_tipagem_limpeza
)

SELECT *
FROM temp_tratamento_enriquecimento