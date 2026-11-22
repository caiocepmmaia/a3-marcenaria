-- =============================================================================
-- Projeto A3 - Controle de Encomendas e Pagamentos de uma Marcenaria
-- Arquivo: sql/03_consultas.sql (10 Consultas SQL)
-- =============================================================================

-- Q01: Carteira geral de pedidos com cliente, valor total, valor já pago, saldo devedor e peso no faturamento (Window Function)
SELECT p.pedido_id,
       c.nome AS cliente,
       p.status,
       p.data_entrega_prevista,
       p.valor_total,
       COALESCE(SUM(pg.valor_pago), 0.00) AS total_pago,
       (p.valor_total - COALESCE(SUM(pg.valor_pago), 0.00)) AS saldo_devedor,
       ROUND((p.valor_total / NULLIF(SUM(p.valor_total) OVER (), 0)) * 100, 2) AS pct_faturamento_total
FROM pedido p
         JOIN cliente c ON c.cliente_id = p.cliente_id
         LEFT JOIN pagamento pg ON pg.pedido_id = p.pedido_id
GROUP BY p.pedido_id, c.nome, p.status, p.data_entrega_prevista, p.valor_total
ORDER BY p.pedido_id;

-- Q02: Pedidos aptos a iniciar produção (status CADASTRADO e >= 50% pago - validação RN-01)
SELECT p.pedido_id,
       c.nome AS cliente,
       p.valor_total,
       COALESCE(SUM(pg.valor_pago), 0.00) AS total_pago,
       ROUND((COALESCE(SUM(pg.valor_pago), 0.00) / NULLIF(p.valor_total, 0)) * 100, 2) AS percentual_pago
FROM pedido p
         JOIN cliente c ON c.cliente_id = p.cliente_id
         LEFT JOIN pagamento pg ON pg.pedido_id = p.pedido_id
WHERE p.status = 'CADASTRADO'
GROUP BY p.pedido_id, c.nome, p.valor_total
HAVING COALESCE(SUM(pg.valor_pago), 0.00) >= (p.valor_total * 0.50);

-- Q03: Pedidos prontos para entrega mas bloqueados por saldo financeiro pendente (RN-03)
SELECT p.pedido_id,
       c.nome AS cliente,
       c.telefone,
       p.valor_total,
       COALESCE(SUM(pg.valor_pago), 0.00) AS total_pago,
       (p.valor_total - COALESCE(SUM(pg.valor_pago), 0.00)) AS falta_pagar
FROM pedido p
         JOIN cliente c ON c.cliente_id = p.cliente_id
         LEFT JOIN pagamento pg ON pg.pedido_id = p.pedido_id
WHERE p.status = 'PRONTO'
GROUP BY p.pedido_id, c.nome, c.telefone, p.valor_total
HAVING COALESCE(SUM(pg.valor_pago), 0.00) < p.valor_total;

-- Q04: Margem bruta por pedido (receita do pedido menos custo dos materiais comprados)
WITH custo_por_pedido AS (
    SELECT pedido_id,
           SUM(quantidade * custo_unitario) AS custo_materiais
    FROM compra_material
    GROUP BY pedido_id
)
SELECT p.pedido_id,
       c.nome AS cliente,
       p.status,
       p.valor_total AS receita,
       COALESCE(cm.custo_materiais, 0.00) AS custo_materiais,
       (p.valor_total - COALESCE(cm.custo_materiais, 0.00)) AS lucro_bruto,
       ROUND(((p.valor_total - COALESCE(cm.custo_materiais, 0.00)) / NULLIF(p.valor_total, 0)) * 100, 2) AS margem_pct
FROM pedido p
         JOIN cliente c ON c.cliente_id = p.cliente_id
         LEFT JOIN custo_por_pedido cm ON cm.pedido_id = p.pedido_id
ORDER BY lucro_bruto DESC;

-- Q05: Consumo consolidado de materiais e gasto total por fornecedor
SELECT f.razao_social AS fornecedor,
       m.nome AS material,
       m.unidade,
       SUM(cm.quantidade) AS qtd_total_comprada,
       SUM(cm.quantidade * cm.custo_unitario) AS valor_total_gasto
FROM compra_material cm
         JOIN fornecedor f ON f.fornecedor_id = cm.fornecedor_id
         JOIN material m ON m.material_id = cm.material_id
GROUP BY f.razao_social, m.nome, m.unidade
ORDER BY valor_total_gasto DESC;

-- Q06: Faturamento e quantidade de móveis vendidos por ambiente
SELECT ip.ambiente,
       COUNT(DISTINCT ip.pedido_id) AS qtd_pedidos,
       SUM(ip.quantidade) AS total_pecas,
       SUM(ip.quantidade * ip.valor_unitario) AS faturamento_ambiente
FROM item_pedido ip
         JOIN pedido p ON p.pedido_id = ip.pedido_id
WHERE p.status <> 'CANCELADO'
GROUP BY ip.ambiente
ORDER BY faturamento_ambiente DESC;

-- Q07: Distribuição de recebimentos por forma de pagamento
SELECT forma_pagamento,
       COUNT(*) AS qtd_lancamentos,
       SUM(valor_pago) AS total_recebido,
       ROUND(AVG(valor_pago), 2) AS ticket_medio_parcela
FROM pagamento
GROUP BY forma_pagamento
ORDER BY total_recebido DESC;

-- Q08: Ranking de clientes por volume financeiro contratado (Window Function)
SELECT RANK() OVER (ORDER BY SUM(p.valor_total) DESC) AS posicao,
    c.nome AS cliente,
       COUNT(p.pedido_id) AS total_pedidos,
       SUM(p.valor_total) AS volume_contratado
FROM cliente c
         JOIN pedido p ON p.cliente_id = c.cliente_id
WHERE p.status <> 'CANCELADO'
GROUP BY c.cliente_id, c.nome;

-- Q09: Pedidos em produção ou cadastrados com entrega prevista nos próximos 7 dias (ou atrasados)
SELECT p.pedido_id,
       c.nome AS cliente,
       p.status,
       p.data_entrega_prevista,
       (p.data_entrega_prevista - CURRENT_DATE) AS dias_restantes
FROM pedido p
         JOIN cliente c ON c.cliente_id = p.cliente_id
WHERE p.status IN ('CADASTRADO', 'EM_PRODUCAO')
  AND p.data_entrega_prevista <= (CURRENT_DATE + 7)
ORDER BY p.data_entrega_prevista ASC;

-- Q10: Histórico completo de auditoria de transições de status por pedido
SELECT a.aud_id,
       a.pedido_id,
       c.nome AS cliente,
       COALESCE(a.status_anterior, '(CRIAÇÃO)') AS de_status,
       a.status_novo AS para_status,
       a.usuario_banco,
       a.data_hora
FROM auditoria_pedido a
         JOIN pedido p ON p.pedido_id = a.pedido_id
         JOIN cliente c ON c.cliente_id = p.cliente_id
ORDER BY a.pedido_id, a.data_hora;