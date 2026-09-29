-- Geração da tabela de dimensão data de forma física, ou seja a persistência e geração dela será através
{{ config(
    materialized='table'
) }}

-- Utilização do pacote date_spine para geração das datas de forma dinâmica
WITH temp_datas_dinamicas AS (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2015-01-01' as date)",
        end_date="cast('2040-12-31' as date)"
    ) }}
),

-- Realiza cast apenas para garantir que seja uma data e não timestamp
temp_datas AS (
    SELECT CAST(date_day AS DATE) AS data_dia
    FROM temp_datas_dinamicas
),

-- Consulta responsável por realizar a extração da data em informações de período, como ano, mês e por ai em diante
temp_atributos AS (
    SELECT data_dia AS dt_registro,
           EXTRACT(YEAR FROM data_dia) AS nr_ano,
           EXTRACT(QUARTER FROM data_dia) AS nr_trimestre,
           EXTRACT(MONTH FROM data_dia) AS nr_mes,
           EXTRACT(DAY FROM data_dia) AS nr_dia_do_mes,

           -- Trás o número do dia da semana
           {{ dbt_date.day_of_week('data_dia', isoweek=true) }} AS nr_dia_da_semana
    FROM temp_datas
)

SELECT {{ dbt_utils.generate_surrogate_key(['dt_registro']) }} AS sk_data,
       dt_registro,
       nr_ano,
       nr_trimestre,
       nr_mes,
       nr_dia_do_mes,
       CAST(nr_ano AS VARCHAR) || '-' || LPAD(CAST(nr_mes AS VARCHAR), 2, '0') AS des_ano_mes,

       -- Converte o número do mÊs para descritivo
       CASE nr_mes
            WHEN 1  THEN 'Janeiro'
            WHEN 2  THEN 'Fevereiro'
            WHEN 3  THEN 'Março'
            WHEN 4  THEN 'Abril'
            WHEN 5  THEN 'Maio'     
            WHEN 6  THEN 'Junho'
            WHEN 7  THEN 'Julho'
            WHEN 8  THEN 'Agosto'
            WHEN 9  THEN 'Setembro'
            WHEN 10 THEN 'Outubro'
            WHEN 11 THEN 'Novembro'
            WHEN 12 THEN 'Dezembro'
        END AS des_nome_mes,

        nr_dia_da_semana,

        -- Converte o dia da semana para o descritivo
        CASE nr_dia_da_semana
            WHEN 1 THEN 'Segunda-feira'
            WHEN 2 THEN 'Terça-feira'
            WHEN 3 THEN 'Quarta-feira'
            WHEN 4 THEN 'Quinta-feira'
            WHEN 5 THEN 'Sexta-feira'
            WHEN 6 THEN 'Sábado'
            WHEN 7 THEN 'Domingo'
        END AS nome_dia_semana,

        -- Flag que identifica se a data é um final de semana
        nr_dia_da_semana IN (6, 7) AS flg_fim_semana
FROM temp_atributos
