-- Consulta primária, que realiza a busca de todas as consultas da source, justamente no arquivo _stg_sources.yml
WITH temp_fonte AS (
    SELECT *
    FROM {{ source('raw_rentcars', 'raw_sessions') }}
),

-- Consulta temporária com objetivo de realizar a deduplicação das informações que vem diretamente dos arquivos em raw.
temp_desduplicado AS (
    SELECT *,
           ROW_NUMBER() OVER (
            PARTITION BY session_id 
            ORDER BY started_at DESC
        ) AS rank
    FROM temp_fonte
),

-- Consulta temporária responsável por realizar a mudança do data type abaixo, renomear as colunas e realizar operações de
-- padronização dos dados e limpeza, com base no UPPER e TRIM, além disso, garantir a normalização primária das informações
-- que vem dos arquivos raw.
temp_conversao_tipagem_limpeza AS (
    SELECT CAST(session_id AS VARCHAR)                     AS id_sessao,
           CAST(user_id AS VARCHAR)                        AS id_usuario,
           CAST(started_at AS TIMESTAMP)                   AS dt_hora_inicio,
           CAST(ended_at AS TIMESTAMP)                     AS dt_hora_fim,
           UPPER(TRIM(CAST(channel AS VARCHAR)))           AS des_canal_aquisicao,
           UPPER(TRIM(CAST(device AS VARCHAR)))            AS tp_dispositivo, -- Aqui existe problema de desnormalização das informações, que são resolvidas com UPPER e TRIM, unificando as infos
           UPPER(TRIM(CAST(country AS VARCHAR)))           AS cod_pais_origem, -- O problema de desnormalização ocorre aqui também, e é resolvido com base no TRIM e UPPER que unifica as informações
           CAST(page_views AS INTEGER)                     AS qt_paginas_vistas,
           UPPER(TRIM(CAST(utm_source AS VARCHAR)))        AS des_utm_origem,
           UPPER(TRIM(CAST(utm_campaign AS VARCHAR)))      AS des_utm_campanha,
           CAST(is_bot AS BOOLEAN)                         AS flg_bot 
    FROM temp_desduplicado
    WHERE rank = 1
),

-- Temporária referente a tratar e transformar valores nulos e aplicar a construção de novos campos com base já nos existentes
-- o intuito da consulta abaixo, é reaproveitar a temp_conversao_tipagem_limpeza, que já realizou toda mudança de nomenclatura, tipagem
-- e deixar abaixo, a temp_tratamento_nulificacao, somnete responsável por realizar as devidas operações
temp_tratamento_nulificacao AS (
    SELECT id_sessao,
           id_usuario,
           dt_hora_inicio,
           dt_hora_fim,
           COALESCE(des_canal_aquisicao, 'NÃO INFORMADO') AS des_canal_aquisicao,
           tp_dispositivo,
           cod_pais_origem,

           -- No CASE (assim como em outros casos do case) abaixo para realizar um de-para o ideal seria o consumo em uma etapa anterior nas temps,
           -- consumindo uma tabela auxiliar para realizar um join, ou até mesmo subir um seed via dbt com os países, para evitar deixar hard code.
           -- facilitando manutenções futuras e escalabilidade           
           CASE
              WHEN cod_pais_origem = 'BR' THEN 'BRASIL'
              WHEN cod_pais_origem = 'MX' THEN 'MÉXICO'
              WHEN cod_pais_origem = 'CO' THEN 'COLOMBIA'
              WHEN cod_pais_origem = 'CL' THEN 'CHILE'
              WHEN cod_pais_origem = 'AR' THEN 'ARGENTINA'
              WHEN cod_pais_origem = 'US' THEN 'ESTADOS UNIDOS'
              WHEN cod_pais_origem = 'PE' THEN 'PERU'
              ELSE 'NÃO PREENCHIDO'
           END AS des_pais_operacao, 
                     
           qt_paginas_vistas,

           -- Como no dicionário, quando o utm_source for nulo, quer dizer que o tráfego está sem rastreamento
           COALESCE(des_utm_origem, 'SEM RASTREAMENTO') AS des_utm_origem,

           des_utm_campanha,
           flg_bot,

           -- Campo que trata o nulo do user_id, que demonstra que a sessão é anônima de acordo com o dicionário de dados
           id_usuario IS NULL AS flg_sessao_anonima
    FROM temp_conversao_tipagem_limpeza
)

SELECT *
FROM temp_tratamento_nulificacao