
-- Teste customizado conforme o case. É um teste para garantir que o valor da coluna que for testada
-- seja menor ou igual ao valor da coluna em comparação
{% test assert_valor_nao_excede(model, column_name, compare_column) %}

SELECT *
FROM {{ model }}
WHERE {{ column_name }} > {{ compare_column }}

{% endtest %}