-- Objetivo: Cruzar as sessões dos usuários com as buscas realizadas.
-- Regras de Negócio:
--    Agrega a quantidade de buscas efetuadas na mesma sessão.
--      Identifica se a sessão gerou clique em oferta e qual foi o menor preço visualizado.
--      Flag se a sessão teve comportamento de busca sem conversão.

-- Consulta que retorna todas as sessões dado a regra fornecida até mesmo com o Stakeholder
-- onde querem verificar somente sessões que não foram suspeitas de bot e que também
-- a hora da sessão final seja verídica, ou seja maior que a hora de início
WITH temp_sessoes AS (
    SELECT *
    FROM {{ ref('stg_sessoes') }}
    WHERE flg_bot = false
        AND dt_hora_fim >= dt_hora_inicio   
),

-- Consulta auxiliar, que busca entender e metrificar a quantidade de buscas que ocorreram dentro das sessões
temp_buscas AS (
    SELECT id_sessao,
           COUNT(DISTINCT id_busca) AS qt_total_buscas,
           MIN(vlr_menor_preco_exibido) AS vlr_menor_preco_pesquisado,
           MAX(
                CASE
                    WHEN flg_usuario_nao_clicou = FALSE THEN 1 
                    ELSE 0
                END
            ) AS flg_houve_clique,
            CASE
                WHEN COUNT(DISTINCT id_busca) > 50 THEN TRUE
                ELSE false
            END AS flg_volume_busca_anormal
    FROM {{ ref('stg_buscas') }}
    GROUP BY id_sessao
)

-- Consulta que tem por finalidade fornecer dados de sessões enriquecidos com os valores quantitativos
-- das buscas que foram realizadas pelos usuários da plataforma
SELECT {{ dbt_utils.generate_surrogate_key(['tse.id_sessao']) }} AS sk_sessao,
       tse.id_sessao,
       tse.id_usuario,
       tse.dt_hora_inicio,
       tse.dt_hora_fim,

       -- Quantidade de duração da sessão em minutos
       COALESCE(DATEDIFF('minute', tse.dt_hora_inicio, tse.dt_hora_fim), 0) AS qt_duracao_sessao_minutos,

       tse.des_canal_aquisicao,
       tse.tp_dispositivo,
       tse.des_pais_operacao,
       tse.cod_pais_origem,
       
       -- Quantidadde de páginas vistas é tradado como zero caso seja nulo
       COALESCE(tse.qt_paginas_vistas, 0) AS qt_paginas_vistas,

       tse.des_utm_origem,
       tse.des_utm_campanha,
       tse.flg_bot,
       tse.flg_sessao_anonima,
       
       -- Quantidade total de buscas realizadas na sessão
       COALESCE(tbu.qt_total_buscas, 0) AS qt_total_buscas,

       -- Menor valor pesquisado caso Nulo significa 0, pois os stakeholders assumem que foi 0
       COALESCE(tbu.vlr_menor_preco_pesquisado, 0) vlr_menor_preco_pesquisado,

       -- Verifica se ocorreu algum clique durante as buscas 
       CASE
            WHEN COALESCE(tbu.flg_houve_clique, 0) = 1 THEN TRUE
            ELSE FALSE
       END AS flg_houve_clique,

       -- Verifica se as buscas se tratam de algo não normal para fins de investigação
       COALESCE(tbu.flg_volume_busca_anormal, false) AS flg_volume_busca_anormal
FROM temp_sessoes tse
    LEFT JOIN temp_buscas tbu ON tse.id_sessao = tbu.id_sessao