-- Configurações iniciais, toda nova rodada de execução dessa dimensão, ela será persistida em uma tabela
-- e de acordo com os Stakeholders, não existe necessidade de armazenar o histórico da tabela em si, 
{{ config(
    materialized='table'
) }}

-- Lista de variáveis que serão utilizadas para criar campos dinâmicos no ato de agrupamento via usuário
{% set dispositivos = ['MOBILE', 'DESKTOP', 'TABLET'] %}

-- Consulta que trás todas as informações referente as sessões que possuem dados e informações dos usuários
WITH temp_int_sessoes AS (
    SELECT *
    FROM {{ ref('int_sessoes_enriquecidas') }}
),

-- Consulta referente a geração das informações que descrevem os usuários, e suas características dentro
-- da plataforma, e como ocorrem os comportamentos do mesmo diante do uso.
temp_agrupado_usuario AS (
    SELECT id_usuario,
        
           -- Primeiro acesso na plataforma, através do monitoramento de sessões
           MIN(dt_hora_inicio) AS dt_primeira_sessao,

           -- Hora da última sessão
           MAX(dt_hora_fim) AS dt_ultima_sessao,

           -- Quantidade total de buscas realizads
           SUM(qt_total_buscas) AS qt_total_buscas_historico,

           -- Quantidade total de minutos somando todas as sessões
           SUM(qt_duracao_sessao_minutos) AS qt_minutos_total_sessao,

           -- Quantidade média de duração em minutos por sessão
           AVG(qt_duracao_sessao_minutos) AS qt_media_minutos_sessao,

           -- Verifica a quantidade de sessões anonimas que este usuário já teve
           SUM(
                CASE
                  WHEN flg_sessao_anonima THEN 1
                  ELSE 0
                END
            ) AS qt_sessoes_anonimas,

            -- Quantidade total de cliques que já realizou
            SUM(
                CASE
                  WHEN flg_houve_clique THEN 1
                  ELSE 0
                END
            ) AS qt_total_reservas_historico,   

            -- Média de preço pesquisado que usuário realiza         
            AVG(vlr_menor_preco_pesquisado) AS vlr_preco_medio_pesquisado,

            -- Jinja dinâmico para compor 3 colunas que verifica a quantidade de acessos realizados
            -- por diferentes dispositivos, para fins de entendimento e comportamento do usuário
            {% for dispositivo in dispositivos %} -- loop percorre o set declaro no começo do script
                SUM(
                    CASE
                        WHEN tp_dispositivo = '{{ dispositivo }}' THEN 1
                        ELSE 0
                    END
                ) AS qt_acesso_{{ dispositivo | lower }}{% if not loop.last %},{% endif %} -- if para determinar quando colocar ou não vírgula, para não ocorrer erro de syntax
            {% endfor %}
    FROM temp_int_sessoes
    GROUP BY id_usuario
)

-- Tabela que acrescenta a surrogate key ao usuário e realiza a reodenação das colunas
SELECT {{ dbt_utils.generate_surrogate_key(['id_usuario']) }} as sk_usuario,
       id_usuario,
       dt_primeira_sessao,
       dt_ultima_sessao,
       vlr_preco_medio_pesquisado,
       qt_total_buscas_historico,
       qt_total_reservas_historico,
       qt_minutos_total_sessao,
       qt_media_minutos_sessao,
       qt_sessoes_anonimas,
       qt_acesso_mobile,
       qt_acesso_tablet,
       qt_acesso_desktop
FROM temp_agrupado_usuario

-- De acordo com negócio, precisam garantir que não passe nulos e querem evitar de serem
-- tratados para não prejudicar as análises e poder corromper questões processuais
WHERE id_usuario IS NOT NULL 