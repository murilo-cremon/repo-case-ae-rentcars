-- Consulta primária, que realiza a busca de todas as consultas da source, justamente no arquivo _stg_sources.yml
WITH temp_fonte AS (
    SELECT *
    FROM {{ source('raw_rentcars', 'raw_partners') }}
),

-- Consulta temporária com objetivo de realizar a deduplicação das informações que vem diretamente dos arquivos em raw.
temp_desduplicado AS (
    SELECT *, -- Nesse caso poderia usar distinct, porém, feito com row number para garantir que no mínimo peguemos o registro mais
           ROW_NUMBER() OVER (
               PARTITION BY partner_id 
               ORDER BY updated_at DESC, created_at DESC
           ) AS rn
    FROM temp_fonte
),

-- Consulta temporária responsável por realizar a mudança do data type abaixo, renomear as colunas e realizar operações de
-- padronização dos dados e limpeza, com base no UPPER e TRIM, além disso, garantir a normalização primária das informações
-- que vem dos arquivos raw.
temp_conversao_tipagem_limpeza AS (
    SELECT CAST(partner_id AS VARCHAR)                     AS id_parceiro,
           UPPER(TRIM(CAST(partner_name AS VARCHAR)))      AS nome_parceiro,
           UPPER(TRIM(CAST(country AS VARCHAR)))           AS cod_pais_operacao,
           UPPER(TRIM(CAST(tier AS VARCHAR)))              AS des_categoria_comercial,

           -- Dado UPPER e TRIM, já resolve o problema do mesmo status escrito de forma distinta, normalizando os dados
           UPPER(TRIM(CAST(status AS VARCHAR)))            AS tp_status_parceiro,

           CAST(commission_rate AS DECIMAL(5,4))           AS vlr_taxa_comissao,
           CAST(created_at AS TIMESTAMP)                   AS dt_hora_cadastro,
           CAST(updated_at AS TIMESTAMP)                   AS dt_hora_atualizacao,
           LOWER(TRIM(CAST(contact_email AS VARCHAR)))     AS email_contato
    FROM temp_desduplicado
    WHERE rn = 1
),

-- Temporária referente a tratar e transformar valores nulos e aplicar a construção de novos campos com base já nos existentes
-- o intuito da consulta abaixo, é reaproveitar a temp_conversao_tipagem_limpeza, que já realizou toda mudança de nomenclatura, tipagem
-- e deixar abaixo, a temp_tratamento_nulificacao, somnete responsável por realizar as devidas operações
temp_tratamento_nulificacao AS (
    SELECT id_parceiro,
           nome_parceiro,
           cod_pais_operacao,

           -- No CASE abaixo para realizar um de-para o ideal seria o consumo em uma etapa anterior nas temps, consumindo uma tabela
           -- auxiliar para realizar um join, ou até mesmo subir um seed via dbt com os países, para evitar deixar hard code.
           -- facilitando manutenções futuras e escalabilidade
           CASE
              WHEN cod_pais_operacao = 'BR' THEN 'BRASIL'
              WHEN cod_pais_operacao = 'MX' THEN 'MÉXICO'
              WHEN cod_pais_operacao = 'CO' THEN 'COLOMBIA'
              WHEN cod_pais_operacao = 'CL' THEN 'CHILE'
              WHEN cod_pais_operacao = 'AR' THEN 'ARGENTINA'
              WHEN cod_pais_operacao = 'US' THEN 'ESTADOS UNIDOS'
              ELSE 'NÃO PREENCHIDO'
           END AS des_pais_operacao,
           
            -- Aplicação como está no dicinário de dados, caso seja nulo, significa não classificado           
           CASE
              WHEN des_categoria_comercial = 'GOLD' THEN 'OURO'
              WHEN des_categoria_comercial = 'SILVER' THEN 'PRATA'
              WHEN des_categoria_comercial = 'BRONZE' THEN 'BRONZE'
              WHEN des_categoria_comercial IS NULL THEN 'NAO_CLASSIFICACAO'
           END AS des_categoria_comercial,
           
           -- Embora não tenha na base o status suspended, já realizarmos o tratamento para fins futuros de inclusão
           CASE
              WHEN tp_status_parceiro = 'ACTIVE' THEN 'ATIVO'
              WHEN tp_status_parceiro = 'INACTIVE' THEN 'INATIVO'
              ELSE 'SUSPENSO'
           END AS tp_status_parceiro,

           vlr_taxa_comissao,
           dt_hora_cadastro,
           dt_hora_atualizacao,
           email_contato
    FROM temp_conversao_tipagem_limpeza
)

SELECT *
FROM temp_tratamento_nulificacao