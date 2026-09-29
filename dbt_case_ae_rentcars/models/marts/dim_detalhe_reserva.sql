-- Configurações iniciais, toda nova rodada de execução dessa dimensão, ela será persistida em uma tabela
-- e se trata de uma JUNK DIMENSION, que é referente a armazenar as informações e dados que precisam ser analisados
-- mas que não se encaixam em nenhuma outra dimensão
{{ config(
    materialized='table'
) }}

-- Consulta que busca os dados da de detalhe da reserva com o objetivo de criar um JUNK DIMENSION para popular as informações
-- que descrevem ainda mais a reserva e o fato em si, o objetivo da junk dimension é incluir campos que não fazem parte de outras
-- dimensões mas que precisam estar presentes nas análises. Isso é uma solicitação direta dos stakeholders que gostariam de 
-- visualizar as informações por esses campos abaixos.
WITH temp_dim_junk_reservas AS (
    SELECT DISTINCT 
           des_local_retirada,
           des_categoria_veiculo,
           des_forma_pagamento,
           cod_moeda
    FROM {{ ref('int_reservas_com_cancelamento') }}
)

-- Geração da surrogate key e reorganização dos campos
SELECT {{ dbt_utils.generate_surrogate_key(['des_local_retirada', 'des_categoria_veiculo', 'des_forma_pagamento', 'cod_moeda']) }} AS sk_detalhe_reserva,
       des_local_retirada,
       des_categoria_veiculo,
       des_forma_pagamento,
       cod_moeda
FROM temp_dim_junk_reservas