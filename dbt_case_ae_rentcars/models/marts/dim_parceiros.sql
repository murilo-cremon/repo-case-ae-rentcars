-- Configurações iniciais, toda nova rodada de execução dessa dimensão, ela será persistida em uma tabela
-- e de acordo com os Stakeholders, não existe necessidade de armazenar o histórico da tabela em si, 
-- pois essa dimensão ela sempre deverá trazer os parceiros ATIVOS e também, com as informações sempre atualizadas
{{ config(
    materialized='table'
) }}

-- Consulta temporária da CTE que trás todos os campos referente ao parceiro para criação da dimensão
-- além disso, já realiza a reodenação de colunas para maior fluídez dos campos
WITH temp_int_parceiro AS (
    SELECT sk_parceiro,
           id_parceiro,
           nome_parceiro,
           cod_pais_operacao,
           des_pais_operacao,
           des_categoria_comercial,
           dt_hora_cadastro,
           dt_hora_atualizacao,
           email_contato,
           vlr_taxa_comissao,
           vlr_comissao_estimada,
           vlr_taxa_comissao_ajustada,
           vlr_total_transacionado,
           vlr_total_receita_liquida,
           qt_total_reservas,
           flg_comissao_ajustada
    FROM {{ ref('int_desempenho_parceiro') }}
)

-- Realiza apenas a renderização para fins de persistência da tabela da dimensão
SELECT *
FROM temp_int_parceiro