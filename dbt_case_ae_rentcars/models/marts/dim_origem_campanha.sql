-- Configurações iniciais, toda nova rodada de execução dessa dimensão, ela será persistida em uma tabela
-- para ser uma dimensão que comportará as informações básicas de campanha e origem de aquisição do consumidor
{{ config(
    materialized='table'
) }}

-- Consulta que busca os dados de canais e origem para entender como o usuário chegou a plataforma, com o objetivo de criar um JUNK DIMENSION para popular as informações
-- que descrevem ainda mais a reserva e o fato em si, o objetivo da junk dimension é incluir campos que não fazem parte de outras
-- dimensões mas que precisam estar presentes nas análises. Isso é uma solicitação direta dos stakeholders que gostariam de 
-- visualizar as informações por esses campos abaixos.
WITH temp_dim_junk_origem AS (
    SELECT DISTINCT 
           des_canal_aquisicao,
           des_utm_origem,
           des_utm_campanha,
           des_pais_operacao,
           tp_dispositivo
    FROM {{ ref('int_sessoes_enriquecidas') }}
)

-- Geração da surrogate key e reorganização dos campos
SELECT {{ dbt_utils.generate_surrogate_key(['des_canal_aquisicao', 'des_utm_origem', 'des_utm_campanha', 'tp_dispositivo', 'des_pais_operacao']) }} AS sk_origem_campanha,
       des_canal_aquisicao,
       des_utm_origem,
       des_utm_campanha,
       tp_dispositivo,
       des_pais_operacao
FROM temp_dim_junk_origem