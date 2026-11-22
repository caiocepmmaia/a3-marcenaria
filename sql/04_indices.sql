-- =============================================================================
-- Projeto A3 - Controle de Encomendas e Pagamentos de uma Marcenaria
-- Arquivo: sql/04_indices.sql
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_pedido_cliente_status  ON pedido (cliente_id, status);
CREATE INDEX IF NOT EXISTS idx_pedido_entrega_status  ON pedido (status, data_entrega_prevista);
CREATE INDEX IF NOT EXISTS idx_item_pedido_pedido     ON item_pedido (pedido_id);
CREATE INDEX IF NOT EXISTS idx_pagamento_pedido       ON pagamento (pedido_id);
CREATE INDEX IF NOT EXISTS idx_compra_pedido          ON compra_material (pedido_id);
CREATE INDEX IF NOT EXISTS idx_compra_mat_forn        ON compra_material (material_id, fornecedor_id);
CREATE INDEX IF NOT EXISTS idx_auditoria_pedido_data  ON auditoria_pedido (pedido_id, data_hora);