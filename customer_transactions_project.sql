USE final_project;

-- ==========================================
-- ЗАДАЧА 1. Список клиентов с непрерывной историей за год
-- ==========================================

-- Шаг 1. Преобразуем текстовую дату транзакции в формат даты MySQL 
-- и подготавливаем базу для фильтрации
WITH parsed_transactions AS (
    SELECT 
        ID_client,
        Sum_payment,
        id_check,
        STR_TO_DATE(date_new, '%d/%m/%Y') AS trans_date
    FROM transactions_info
),

-- Шаг 2. Фильтруем транзакции строго по заданному годовому периоду (с 01.06.2015 по 01.06.2016)
filtered_trans AS (
    SELECT *
    FROM parsed_transactions
    WHERE trans_date >= '2015-06-01' AND trans_date <= '2016-06-01'
),

-- Шаг 3. Группируем транзакции клиентов по месяцам, чтобы выявить уникальные месяцы активности
client_monthly AS (
    SELECT 
        ID_client,
        DATE_FORMAT(trans_date, '%Y-%m-01') AS trans_month
    FROM filtered_trans
    GROUP BY ID_client, DATE_FORMAT(trans_date, '%Y-%m-01')
),

-- Шаг 4. Отбираем только тех клиентов, у которых ровно 12 уникальных месяцев активности (без пропусков)
continuous_clients AS (
    SELECT ID_client
    FROM client_monthly
    GROUP BY ID_client
    HAVING COUNT(DISTINCT trans_month) = 12
),

-- Шаг 5. Рассчитываем ключевые метрики для каждого клиента за весь период:
-- общее количество операций, общую сумму, средний чек и среднюю сумму покупок в месяц
client_metrics AS (
    SELECT 
        ID_client,
        COUNT(id_check) AS total_operations,
        SUM(Sum_payment) AS total_amount,
        SUM(Sum_payment) / COUNT(id_check) AS avg_check_period,
        SUM(Sum_payment) / 12.0 AS avg_monthly_amount
    FROM filtered_trans
    GROUP BY ID_client
)

-- Финальный вывод: соединяем список непрерывных клиентов с их метриками
SELECT 
    cc.ID_client,
    cm.total_operations,
    ROUND(cm.total_amount, 2) AS total_amount,
    ROUND(cm.avg_check_period, 2) AS avg_check_period,
    ROUND(cm.avg_monthly_amount, 2) AS avg_monthly_amount
FROM continuous_clients cc
JOIN client_metrics cm ON cc.ID_client = cm.ID_client;


-- ==========================================
-- ЗАДАЧА 2. Информация в разрезе месяцев
-- ==========================================
WITH parsed_transactions AS (
    SELECT 
        ID_client,
        Sum_payment,
        id_check,
        STR_TO_DATE(date_new, '%d/%m/%Y') AS trans_date
    FROM transactions_info
),
filtered_trans AS (
    SELECT *
    FROM parsed_transactions
    WHERE trans_date >= '2015-06-01' AND trans_date <= '2016-06-01'
),
-- Шаг 1. Считаем общие итоги за весь год для дальнейшего расчета процентных долей
year_totals AS (
    SELECT 
        COUNT(id_check) AS total_year_ops,
        SUM(Sum_payment) AS total_year_amount
    FROM filtered_trans
),
-- Шаг 2. Агрегируем данные в разрезе каждого месяца
monthly_base AS (
    SELECT 
        DATE_FORMAT(trans_date, '%Y-%m') AS trans_month,
        AVG(Sum_payment) AS avg_check_month,
        COUNT(id_check) AS operations_count_month,
        COUNT(DISTINCT ID_client) AS active_clients_month,
        SUM(Sum_payment) AS amount_month
    FROM filtered_trans
    GROUP BY DATE_FORMAT(trans_date, '%Y-%m')
)
-- Шаг 3. Формируем итоговую таблицу с расчетом средних показателей и долей в процентах
SELECT 
    mb.trans_month,
    ROUND(mb.avg_check_month, 2) AS avg_check_month,
    mb.operations_count_month,
    mb.active_clients_month,
    -- Доля операций месяца от общего числа операций за год (%)
    ROUND((mb.operations_count_month * 100.0 / yt.total_year_ops), 2) AS ops_share_pct,
    -- Доля суммы месяца от общей суммы за год (%)
    ROUND((mb.amount_month * 100.0 / yt.total_year_amount), 2) AS amount_share_pct
FROM monthly_base mb
CROSS JOIN year_totals yt
ORDER BY mb.trans_month;



-- ==========================================
-- ЗАДАЧА 3. Соотношение M / F / NA по месяцам и доля затрат
-- ==========================================

-- Шаг 1. Преобразуем текстовую дату в формат даты MySQL
WITH parsed_transactions AS (
    SELECT 
        ID_client,
        Sum_payment,
        id_check,
        STR_TO_DATE(date_new, '%d/%m/%Y') AS trans_date
    FROM transactions_info
),

-- Шаг 2. Фильтруем транзакции по заданному годовому периоду
filtered_trans AS (
    SELECT *
    FROM parsed_transactions
    WHERE trans_date >= '2015-06-01' AND trans_date <= '2016-06-01'
),

-- Шаг 3. Соединяем транзакции с клиентами (учитываем регистр Id_client) 
-- и группируем по месяцам и полу (пропуски маркируем как 'NA')
monthly_gender_stats AS (
    SELECT 
        DATE_FORMAT(ft.trans_date, '%Y-%m') AS trans_month,
        COALESCE(ci.Gender, 'NA') AS gender,
        COUNT(ft.id_check) AS ops_by_gender,
        SUM(ft.Sum_payment) AS amount_by_gender
    FROM filtered_trans ft
    LEFT JOIN customer_info ci ON ft.ID_client = ci.Id_client
    GROUP BY DATE_FORMAT(ft.trans_date, '%Y-%m'), COALESCE(ci.Gender, 'NA')
),

-- Шаг 4. Считаем общие итоги по каждому месяцу для вычисления процентных долей
monthly_totals AS (
    SELECT 
        DATE_FORMAT(trans_date, '%Y-%m') AS trans_month,
        COUNT(id_check) AS total_month_ops,
        SUM(Sum_payment) AS total_month_amount
    FROM filtered_trans
    GROUP BY DATE_FORMAT(trans_date, '%Y-%m')
)

-- Шаг 5. Выводим результаты: доли операций и долю затрат для каждого пола по месяцам
SELECT 
    mgs.trans_month,
    mgs.gender,
    mgs.ops_by_gender,
    ROUND((mgs.ops_by_gender * 100.0 / mt.total_month_ops), 2) AS gender_ops_pct,
    ROUND((mgs.amount_by_gender * 100.0 / mt.total_month_amount), 2) AS gender_amount_share_pct
FROM monthly_gender_stats mgs
JOIN monthly_totals mt ON mgs.trans_month = mt.trans_month
ORDER BY mgs.trans_month, mgs.gender;


-- ==========================================
-- ЗАДАЧА 4. Возрастные группы (шаг 10 лет) + квартальная аналитика
-- ==========================================

-- Шаг 1. Преобразуем текстовую дату транзакции в формат даты MySQL
WITH parsed_transactions AS (
    SELECT 
        ID_client,
        Sum_payment,
        id_check,
        STR_TO_DATE(date_new, '%d/%m/%Y') AS trans_date
    FROM transactions_info
),

-- Шаг 2. Фильтруем транзакции по заданному годовому периоду (с 01.06.2015 по 01.06.2016)
filtered_trans AS (
    SELECT *
    FROM parsed_transactions
    WHERE trans_date >= '2015-06-01' AND trans_date <= '2016-06-01'
),

-- Шаг 3. Соединяем транзакции с информацией о клиентах, формируем кварталы и возрастные группы с шагом 10 лет
enriched_trans AS (
    SELECT 
        ft.id_check,
        ft.ID_client,
        ft.Sum_payment,
        ft.trans_date,
        -- Определяем квартал (например, 2015-Q3)
        CONCAT(YEAR(ft.trans_date), '-Q', QUARTER(ft.trans_date)) AS quarter_str,
        COALESCE(ci.Gender, 'NA') AS gender,
        COALESCE(ci.Age, -1) AS age,
        -- Распределяем клиентов по возрастным группам с шагом 10 лет (и выделяем NA для отсутствующих данных)
        CASE 
            WHEN ci.Age IS NULL THEN 'NA'
            WHEN ci.Age BETWEEN 0 AND 9 THEN '0-9'
            WHEN ci.Age BETWEEN 10 AND 19 THEN '10-19'
            WHEN ci.Age BETWEEN 20 AND 29 THEN '20-29'
            WHEN ci.Age BETWEEN 30 AND 39 THEN '30-39'
            WHEN ci.Age BETWEEN 40 AND 49 THEN '40-49'
            WHEN ci.Age BETWEEN 50 AND 59 THEN '50-59'
            WHEN ci.Age BETWEEN 60 AND 69 THEN '60-69'
            WHEN ci.Age BETWEEN 70 AND 79 THEN '70-79'
            ELSE '80+'
        END AS age_group
    FROM filtered_trans ft
    LEFT JOIN customer_info ci ON ft.ID_client = ci.Id_client
),

-- Шаг 4. Считаем общие итоги за весь год для расчета годовых долей в процентах
overall_totals AS (
    SELECT 
        COUNT(id_check) AS total_ops_year,
        SUM(Sum_payment) AS total_amount_year
    FROM enriched_trans
),

-- Шаг 5. Считаем итоги по каждому кварталу для расчета квартальных долей в процентах
quarter_totals AS (
    SELECT 
        quarter_str,
        COUNT(id_check) AS total_ops_q,
        SUM(Sum_payment) AS total_amount_q
    FROM enriched_trans
    GROUP BY quarter_str
),

-- Шаг 6. Агрегируем показатели (количество операций, сумма, средний чек) в разрезе возрастных групп и кварталов
age_group_summary AS (
    SELECT 
        et.age_group,
        et.quarter_str,
        COUNT(et.id_check) AS ops_count,
        SUM(et.Sum_payment) AS total_amount,
        AVG(et.Sum_payment) AS avg_check
    FROM enriched_trans et
    GROUP BY et.age_group, et.quarter_str
)

-- Шаг 7. Финальная выборка с расчетом всех долей за год и за кварталы
SELECT 
    ags.age_group,
    ags.quarter_str,
    ags.ops_count,
    ROUND(ags.total_amount, 2) AS total_amount,
    ROUND(ags.avg_check, 2) AS avg_check,
    -- Доля от общего количества операций за весь год (%)
    ROUND((ags.ops_count * 100.0 / ot.total_ops_year), 2) AS ops_share_year_pct,
    -- Доля от общей суммы за весь год (%)
    ROUND((ags.total_amount * 100.0 / ot.total_amount_year), 2) AS amount_share_year_pct,
    -- Доля от операций конкретного квартала (%)
    ROUND((ags.ops_count * 100.0 / qt.total_ops_q), 2) AS ops_share_quarter_pct,
    -- Доля от суммы конкретного квартала (%)
    ROUND((ags.total_amount * 100.0 / qt.total_amount_q), 2) AS amount_share_quarter_pct
FROM age_group_summary ags
CROSS JOIN overall_totals ot
JOIN quarter_totals qt ON ags.quarter_str = qt.quarter_str
ORDER BY ags.age_group, ags.quarter_str;