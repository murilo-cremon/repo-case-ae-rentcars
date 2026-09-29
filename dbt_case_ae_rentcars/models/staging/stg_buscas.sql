-- Consulta primária, que realiza a busca de todas as consultas da source, justamente no arquivo _stg_sources.yml
WITH temp_fonte AS (
    SELECT *
    FROM {{ source('raw_rentcars', 'raw_searches') }}
),

-- Consulta temporária com objetivo de realizar a deduplicação das informações que vem diretamente dos arquivos em raw.
temp_desduplicado AS (
    SELECT *, -- Nesse caso poderia usar distinct, porém, feito com row number para garantir que no mínimo peguemos o registro mais atualizado
           ROW_NUMBER() OVER (
               PARTITION BY search_id 
               ORDER BY searched_at DESC
           ) AS rank
    FROM temp_fonte
),

-- Consulta temporária responsável por realizar a mudança do data type abaixo, renomear as colunas e realizar operações de
-- padronização dos dados e limpeza, com base no UPPER e TRIM, além disso, garantir a normalização primária das informações
-- que vem dos arquivos raw.
temp_conversao_tipagem_limpeza AS (
    SELECT CAST(search_id AS VARCHAR)                      AS id_busca,
           CAST(session_id AS VARCHAR)                     AS id_sessao,
           CAST(searched_at AS TIMESTAMP)                  AS dt_hora_busca,

           -- Campo com informações duplicadas por conta de erro de persistência, ajustado e normalizado via UPPER, e TRIM para garantir a quebra dos espaços
           UPPER(TRIM(CAST(pickup_location AS VARCHAR)))   AS des_local_retirada,

           -- Assim como o campo acima, realiza a normalização dos dados com base no UPPER e TRIM para evitar deduplicação em nomes
           UPPER(TRIM(CAST(dropoff_location AS VARCHAR)))  AS des_local_devolucao,

           CAST(pickup_date AS DATE)                       AS dt_retirada,
           CAST(dropoff_date AS DATE)                      AS dt_devolucao,
           UPPER(TRIM(CAST(car_category AS VARCHAR)))      AS des_categoria_veiculo,
           CAST(num_results AS INTEGER)                    AS qt_resultados_exibidos,
           CAST(partner_id_clicked AS VARCHAR)             AS id_parceiro_clicado,
           CAST(price_shown AS DECIMAL(10,2))              AS vlr_menor_preco_exibido
    FROM temp_desduplicado
    WHERE rank = 1
),

-- Realização do tratamento dos dados que possuem valores Nulos, adaptando-os juntamente as regras de negócio, observações diretas
-- do dicinonário de dados, e além disso, enriquecendo e criando novas colunas derivadas das existentes, para que facilite o trabalho
-- e manipulação futura das informações. 
temp_tratamento_nulificacao AS (
    SELECT id_busca,
           id_sessao,
           dt_hora_busca,
           des_local_retirada,

           -- Trata via COALESCE o local de devolucao nulo que deve ser o mesmo do retirada, de acordo como está no dicionário de dados
           COALESCE(des_local_devolucao, des_local_retirada) AS des_local_devolucao,

           dt_retirada,
           dt_devolucao,

           -- Trata novamente via COALESCE os valores nulos que é a não seleção de categoria no filtro, como está no dicionário
           COALESCE(des_categoria_veiculo, 'FILTRO NAO APLICADO') AS des_categoria_veiculo,

           qt_resultados_exibidos,
           id_parceiro_clicado,
           vlr_menor_preco_exibido,

           -- Campo criado para identificar se o usuário clicou ou não em algum resultado da pesquisa, facilitando pesquisas e buscas dos resultados
           id_parceiro_clicado IS NULL AS flg_usuario_nao_clicou
    FROM temp_conversao_tipagem_limpeza
)

SELECT *
FROM temp_tratamento_nulificacao