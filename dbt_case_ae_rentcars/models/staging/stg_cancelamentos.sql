-- Consulta primária, que realiza a busca de todas as consultas da source, justamente no arquivo _stg_sources.yml
WITH temp_fonte AS (
    SELECT *
    FROM {{ source('raw_rentcars', 'raw_cancellations') }}
),

-- Consulta temporária com objetivo de realizar a deduplicação das informações que vem diretamente dos arquivos em raw.
temp_desduplicado AS (
    SELECT *, -- Nesse caso poderia usar distinct, porém, feito com row number para garantir que no mínimo peguemos o registro mais atualizado
           ROW_NUMBER() OVER (
               PARTITION BY cancellation_id 
               ORDER BY cancelled_at DESC
           ) AS rank
    FROM temp_fonte
),

-- Consulta temporária responsável por realizar a mudança do data type abaixo, renomear as colunas e realizar operações de
-- padronização dos dados e limpeza, com base no UPPER e TRIM, além disso, garantir a normalização primária das informações
-- que vem dos arquivos raw.
temp_conversao_tipagem_limpeza AS (
    SELECT
        CAST(cancellation_id AS VARCHAR)                AS id_cancelamento,
        CAST(booking_id AS VARCHAR)                     AS id_reserva,
        CAST(cancelled_at AS TIMESTAMP)                 AS dt_hora_cancelamento,
        UPPER(TRIM(CAST(reason AS VARCHAR)))            AS des_motivo_cancelamento,
        UPPER(TRIM(CAST(cancelled_by AS VARCHAR)))      AS des_responsavel_cancelamento,
        CAST(refund_amount AS DECIMAL(10,2))            AS vlr_reembolsado,
        UPPER(TRIM(CAST(refund_status AS VARCHAR)))     AS tp_status_reembolso,
        CAST(days_before_pickup AS INTEGER)             AS qt_dias_antecedencia_retirada
    FROM temp_desduplicado
    WHERE rank = 1
),

-- Realização do tratamento dos dados que possuem valores Nulos, adaptando-os juntamente as regras de negócio, observações diretas
-- do dicinonário de dados, e além disso, enriquecendo e criando novas colunas derivadas das existentes, para que facilite o trabalho
-- e manipulação futura das informações. 
temp_tratamento_nulificacao AS (
    SELECT id_cancelamento,
           id_reserva,
           dt_hora_cancelamento,

           -- Tratamento do motivo de cancelamento para deixar pouco mais amigável e realizado tratamento do Nulo para seguir as regras do dicionário de dados
           COALESCE(TRIM(REPLACE(des_motivo_cancelamento, '_', ' ')), 'NÃO INFORMADO') AS des_motivo_cancelamento,

           -- Conversão das nomenclaturas dada sistematicamente aos responsável pelo cancelamento
           CASE
                WHEN des_responsavel_cancelamento = 'ADMIN' THEN 'ADMINISTRADOR'
                WHEN des_responsavel_cancelamento = 'CUSTOMER' THEN 'CLIENTE'
                WHEN des_responsavel_cancelamento = 'PARTNER' THEN 'PARCEIRO'
                WHEN des_responsavel_cancelamento = 'SYSTEM' THEN 'SISTEMA'
                ELSE 'NÃO PREENCHIDO'
           END des_responsavel_cancelamento,

           vlr_reembolsado,

           -- Conversão da descrição do status para uma maneira mais amigável com intuito de simplificar o entendimento
           CASE
                WHEN tp_status_reembolso = 'PENDING' THEN 'PENDENTE'
                WHEN tp_status_reembolso = 'DENIED' THEN 'NEGADO'
                WHEN tp_status_reembolso = 'PROCESSED' THEN 'PROCESSADO'
                ELSE 'POSSÍVEL CANCELAMENTO'
            END as tp_status_reembolso,

           -- Quantidade de dias é convertido para 0 em caso de nulos para evidenciar que não teve antecipação de acordo com negócio
           COALESCE(qt_dias_antecedencia_retirada, 0) AS qt_dias_antecedencia_retirada,

           -- Flag criada para identificar de forma direta quem foram os cancelamentos que não tinham reembolso aplicável
           tp_status_reembolso IS NULL AS flg_cancelamento_sem_reembolso,

           -- Flag que identifica se os dias de antecedencia de retirada estão negativos, para fins de investigacao
           CASE
                WHEN qt_dias_antecedencia_retirada < 0 THEN TRUE
                ELSE FALSE 
           END AS flg_cancelamento_tardio
    FROM temp_conversao_tipagem_limpeza
)

SELECT *
FROM temp_tratamento_nulificacao