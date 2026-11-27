\set ON_ERROR_STOP on

BEGIN;

DO $teste$
DECLARE
    v_total_pedido NUMERIC;
    v_recebido NUMERIC;
    v_excesso_recusado BOOLEAN := false;
BEGIN
    -- Confere se o pedido 3 está nas condições esperadas para o teste.
    SELECT valor_total INTO v_total_pedido
    FROM public.pedido
    WHERE pedido_id = 3
    FOR UPDATE;

    SELECT SUM(valor_pago) INTO v_recebido
    FROM public.pagamento
    WHERE pedido_id = 3;

    IF v_total_pedido IS DISTINCT FROM 4000.00
       OR v_recebido IS DISTINCT FROM 3500.00 THEN
        RAISE EXCEPTION 'O teste precisa do pedido 3 com total de 4000 e recebido de 3500.';
    END IF;

    -- Caso 1: faltam 500, então um pagamento de 600 deve ser recusado.
    BEGIN
        INSERT INTO public.pagamento (pedido_id, valor_pago, forma_pagamento)
        VALUES (3, 600.00, 'PIX');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM NOT LIKE 'MARCENARIA-003:%' THEN
            RAISE;
        END IF;
        v_excesso_recusado := true;
    END;

    IF NOT v_excesso_recusado THEN
        RAISE EXCEPTION 'FALHA: o banco aceitou 600 quando faltavam 500.';
    END IF;
    RAISE NOTICE 'OK 1: pagamento acima do saldo recusado com MARCENARIA-003.';

    -- Caso 2: pagar exatamente os 500 restantes deve quitar o pedido.
    INSERT INTO public.pagamento (pedido_id, valor_pago, forma_pagamento)
    VALUES (3, 500.00, 'PIX');

    SELECT SUM(valor_pago) INTO v_recebido
    FROM public.pagamento
    WHERE pedido_id = 3;

    IF v_recebido IS DISTINCT FROM 4000.00 THEN
        RAISE EXCEPTION 'FALHA: esperado total recebido de 4000, obtido %.', v_recebido;
    END IF;
    RAISE NOTICE 'OK 2: pagamento exato aceito e pedido quitado.';
END;
$teste$;

ROLLBACK;