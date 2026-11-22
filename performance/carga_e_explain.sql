-- =============================================================================
-- Projeto A3 - Análise de Desempenho (Carga Volumosa + EXPLAIN ANALYZE)
-- Arquivo: performance/carga_e_explain.sql
-- =============================================================================

-- 1. Gera 20.000 pedidos e 20.000 pagamentos sintéticos respeitando ck_pedido_datas
INSERT INTO pedido (cliente_id, data_pedido, data_entrega_prevista, valor_total, status)
SELECT (g % 5) + 1,
       CURRENT_DATE - (g % 180),
       (CURRENT_DATE - (g % 180)) + 15 + (g % 30),
       4000.00,
       CASE (g % 4)
           WHEN 0 THEN 'CADASTRADO'
           WHEN 1 THEN 'EM_PRODUCAO'
           WHEN 2 THEN 'PRONTO'
           ELSE 'ENTREGUE'
           END
FROM generate_series(1, 20000) AS g;

INSERT INTO pagamento (pedido_id, data_pagamento, valor_pago, forma_pagamento)
SELECT p.pedido_id,
       p.data_pedido,
       2000.00,
       'PIX'
FROM pedido p
WHERE p.pedido_id > 5;

ANALYZE pedido;
ANALYZE pagamento;

-- 2. Consulta alvo para comparação no EXPLAIN (ANALYZE, BUFFERS)
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.pedido_id,
       c.nome,
       p.data_entrega_prevista,
       SUM(pg.valor_pago) AS total_pago
FROM pedido p
         JOIN cliente c ON c.cliente_id = p.cliente_id
         JOIN pagamento pg ON pg.pedido_id = p.pedido_id
WHERE p.status = 'EM_PRODUCAO'
  AND p.data_entrega_prevista <= CURRENT_DATE + 7
GROUP BY p.pedido_id, c.nome, p.data_entrega_prevista;