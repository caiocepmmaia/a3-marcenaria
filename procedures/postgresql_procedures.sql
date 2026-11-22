-- =============================================================================
-- Projeto A3 - Controle de Encomendas e Pagamentos de uma Marcenaria
-- Arquivo: procedures/postgresql_procedures.sql (PL/pgSQL)
-- Regras: RN-01 a RN-05 | Sem COMMIT interno (transação controlada por quem chama)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TRIGGER 1 (RN-05): Recalcula automaticamente o valor_total do pedido
-- sempre que um móvel (item_pedido) é inserido, alterado ou removido.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_atualiza_valor_pedido() RETURNS TRIGGER AS $$
DECLARE
v_pedido_id INTEGER;
BEGIN
    v_pedido_id := COALESCE(NEW.pedido_id, OLD.pedido_id);

UPDATE pedido
SET valor_total = COALESCE((
                               SELECT SUM(quantidade * valor_unitario)
                               FROM item_pedido
                               WHERE pedido_id = v_pedido_id
                           ), 0.00)
WHERE pedido_id = v_pedido_id;

RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_atualiza_valor_pedido ON item_pedido;
CREATE TRIGGER trg_atualiza_valor_pedido
    AFTER INSERT OR UPDATE OR DELETE ON item_pedido
    FOR EACH ROW EXECUTE FUNCTION fn_atualiza_valor_pedido();

-- -----------------------------------------------------------------------------
-- TRIGGER 2 (RN-04): Grava histórico contínuo em auditoria_pedido toda vez
-- que o status de um pedido é alterado (inclusive na criação).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_auditoria_pedido() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO auditoria_pedido (pedido_id, status_anterior, status_novo, usuario_banco)
        VALUES (NEW.pedido_id, NULL, NEW.status, current_user);
    ELSIF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO auditoria_pedido (pedido_id, status_anterior, status_novo, usuario_banco)
        VALUES (NEW.pedido_id, OLD.status, NEW.status, current_user);
END IF;
RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_auditoria_pedido ON pedido;
CREATE TRIGGER trg_auditoria_pedido
    AFTER INSERT OR UPDATE OF status ON pedido
    FOR EACH ROW EXECUTE FUNCTION fn_auditoria_pedido();

-- -----------------------------------------------------------------------------
-- PROCEDURE 1 (RN-02): Registra pagamento validando valor > 0, status ativo
-- e teto de 100% do valor_total do pedido.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_pagamento(
    p_pedido_id       INTEGER,
    p_valor_pago      NUMERIC,
    p_forma_pagamento VARCHAR,
    p_data_pagamento  DATE DEFAULT CURRENT_DATE
)
LANGUAGE plpgsql AS $$
DECLARE
v_valor_total NUMERIC;
    v_status      VARCHAR;
    v_ja_pago     NUMERIC;
BEGIN
    IF p_valor_pago IS NULL OR p_valor_pago <= 0 THEN
        RAISE EXCEPTION 'MARCENARIA-002: O valor do pagamento deve ser maior que zero.'
            USING ERRCODE = 'P0001';
END IF;

SELECT valor_total, status
INTO v_valor_total, v_status
FROM pedido
WHERE pedido_id = p_pedido_id
    FOR UPDATE;

IF NOT FOUND THEN
        RAISE EXCEPTION 'MARCENARIA-002: Pedido % inexistente.', p_pedido_id
            USING ERRCODE = 'P0001';
END IF;

    IF v_status IN ('CANCELADO', 'ENTREGUE') THEN
        RAISE EXCEPTION 'MARCENARIA-002: Pedido % com status % não aceita novos pagamentos.', p_pedido_id, v_status
            USING ERRCODE = 'P0001';
END IF;

SELECT COALESCE(SUM(valor_pago), 0.00)
INTO v_ja_pago
FROM pagamento
WHERE pedido_id = p_pedido_id;

IF (v_ja_pago + p_valor_pago) > v_valor_total THEN
        RAISE EXCEPTION 'MARCENARIA-003: Pagamento excede 100%% do pedido (Total: %, Já pago: %, Tentativa: %).',
            v_valor_total, v_ja_pago, p_valor_pago
            USING ERRCODE = 'P0001';
END IF;

INSERT INTO pagamento (pedido_id, data_pagamento, valor_pago, forma_pagamento)
VALUES (p_pedido_id, p_data_pagamento, p_valor_pago, p_forma_pagamento);
END;
$$;

-- -----------------------------------------------------------------------------
-- PROCEDURE 2 (RN-01, RN-03, RN-04): Avança o status do pedido respeitando
-- o fluxo sequencial, os 50% para produção e os 100% para entrega.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_avancar_status_pedido(
    p_pedido_id   INTEGER,
    p_novo_status VARCHAR
)
LANGUAGE plpgsql AS $$
DECLARE
v_status_atual VARCHAR;
    v_valor_total  NUMERIC;
    v_total_pago   NUMERIC;
BEGIN
SELECT status, valor_total
INTO v_status_atual, v_valor_total
FROM pedido
WHERE pedido_id = p_pedido_id
    FOR UPDATE;

IF NOT FOUND THEN
        RAISE EXCEPTION 'MARCENARIA-004: Pedido % inexistente.', p_pedido_id
            USING ERRCODE = 'P0001';
END IF;

SELECT COALESCE(SUM(valor_pago), 0.00)
INTO v_total_pago
FROM pagamento
WHERE pedido_id = p_pedido_id;

-- RN-01: Início da produção exige >= 50% pago e valor_total > 0
IF p_novo_status = 'EM_PRODUCAO' THEN
        IF v_status_atual <> 'CADASTRADO' THEN
            RAISE EXCEPTION 'MARCENARIA-004: Apenas pedidos CADASTRADOS podem ir para EM_PRODUCAO (Atual: %).', v_status_atual
                USING ERRCODE = 'P0001';
END IF;
        IF v_valor_total <= 0 OR v_total_pago < (v_valor_total * 0.50) THEN
            RAISE EXCEPTION 'MARCENARIA-001: Sinal insuficiente para iniciar produção (Mínimo 50%%: %, Pago: %).',
                ROUND(v_valor_total * 0.50, 2), v_total_pago
                USING ERRCODE = 'P0001';
END IF;

    -- Fluxo sequencial para PRONTO
    ELSIF p_novo_status = 'PRONTO' THEN
        IF v_status_atual <> 'EM_PRODUCAO' THEN
            RAISE EXCEPTION 'MARCENARIA-004: Apenas pedidos EM_PRODUCAO podem passar para PRONTO (Atual: %).', v_status_atual
                USING ERRCODE = 'P0001';
END IF;

    -- RN-03: Conclusão da entrega exige status PRONTO e 100% pago
    ELSIF p_novo_status = 'ENTREGUE' THEN
        IF v_status_atual <> 'PRONTO' THEN
            RAISE EXCEPTION 'MARCENARIA-004: O pedido precisa estar PRONTO antes de ser ENTREGUE (Atual: %).', v_status_atual
                USING ERRCODE = 'P0001';
END IF;
        IF v_total_pago < v_valor_total THEN
            RAISE EXCEPTION 'MARCENARIA-005: Saldo pendente impede entrega (Total: %, Pago: %).',
                v_valor_total, v_total_pago
                USING ERRCODE = 'P0001';
END IF;

    -- Cancelamento permitido apenas se ainda não foi entregue
    ELSIF p_novo_status = 'CANCELADO' THEN
        IF v_status_atual = 'ENTREGUE' THEN
            RAISE EXCEPTION 'MARCENARIA-004: Não é possível cancelar um pedido já ENTREGUE.'
                USING ERRCODE = 'P0001';
END IF;
ELSE
        RAISE EXCEPTION 'MARCENARIA-004: Status destino inválido (%).', p_novo_status
            USING ERRCODE = 'P0001';
END IF;

UPDATE pedido
SET status = p_novo_status
WHERE pedido_id = p_pedido_id;
END;
$$;