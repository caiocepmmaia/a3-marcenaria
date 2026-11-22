-- =============================================================================
-- Projeto A3 - Controle de Encomendas e Pagamentos de uma Marcenaria
-- Arquivo: sql/02_inserts.sql
-- =============================================================================

-- 1. Clientes
INSERT INTO cliente (nome, cpf_cnpj, telefone, email) VALUES
                                                          ('Mariana Costa',        '123.456.789-01', '(51) 99111-1001', 'mariana.costa@email.com'),
                                                          ('Ricardo Almeida',      '234.567.890-02', '(51) 99222-2002', 'ricardo.almeida@email.com'),
                                                          ('Fernanda Souza',       '345.678.901-03', '(51) 99333-3003', 'fernanda.souza@email.com'),
                                                          ('Construtora Horizonte','12.345.678/0001-90', '(51) 3344-4004', 'compras@horizonte.com.br'),
                                                          ('Carlos Eduardo Lima',  '456.789.012-04', '(51) 99555-5005', 'carlos.lima@email.com');

-- 2. Fornecedores
INSERT INTO fornecedor (razao_social, cnpj, telefone) VALUES
                                                          ('Madeireira Sul Chapas Ltda', '11.111.111/0001-11', '(51) 3211-1000'),
                                                          ('Ferragens & Cia Brasil',     '22.222.222/0001-22', '(51) 3222-2000'),
                                                          ('Tintas e Vernizes Gaúcha',   '33.333.333/0001-33', '(51) 3233-3000');

-- 3. Materiais
INSERT INTO material (nome, unidade) VALUES
                                         ('MDF Branco Tx 18mm',          'CHAPA'),
                                         ('MDF Carvalho Hanover 18mm',   'CHAPA'),
                                         ('MDF Fundo 6mm Branco',        'CHAPA'),
                                         ('Corrediça Telescópica 45cm',  'UN'),
                                         ('Dobradiça Curva Amortecedor', 'UN'),
                                         ('Fita de Borda Carvalho 22mm', 'M'),
                                         ('Cola de Contato 2,8kg',       'L');

-- 4. Pedidos (valor_total inicia em 0 e será calculado pela trigger ao inserir itens)
INSERT INTO pedido (cliente_id, data_pedido, data_entrega_prevista, status) VALUES
                                                                                (1, CURRENT_DATE - 25, CURRENT_DATE - 2,  'ENTREGUE'),    -- Pedido 1: Concluído e 100% pago
                                                                                (2, CURRENT_DATE - 15, CURRENT_DATE + 4,  'EM_PRODUCAO'), -- Pedido 2: Em produção (prazo crítico <= 7 dias)
                                                                                (3, CURRENT_DATE - 10, CURRENT_DATE + 12, 'PRONTO'),      -- Pedido 3: Pronto aguardando quitação/entrega (R$ 4.000)
                                                                                (4, CURRENT_DATE - 3,  CURRENT_DATE + 20, 'CADASTRADO'),  -- Pedido 4: Cadastrado com sinal < 50% (fronteira RN-01)
                                                                                (1, CURRENT_DATE - 1,  CURRENT_DATE + 30, 'CADASTRADO');  -- Pedido 5: Recém-cadastrado sem pagamentos

-- 5. Itens dos Pedidos (disparam trg_atualiza_valor_pedido automaticamente)
INSERT INTO item_pedido (pedido_id, descricao_movel, ambiente, quantidade, valor_unitario) VALUES
-- Pedido 1 (Total: R$ 6.500,00)
(1, 'Cozinha Planejada em L',      'Cozinha',    1, 6500.00),
-- Pedido 2 (Total: R$ 5.200,00)
(2, 'Guarda-Roupa Casal 6 Portas', 'Dormitório', 1, 3800.00),
(2, 'Painel Ripado TV 2,20m',      'Sala',       1, 1400.00),
-- Pedido 3 (Total: R$ 4.000,00 - cenário exato do escopo!)
(3, 'Armário Aéreo + Balcão Pia',  'Cozinha',    1, 4000.00),
-- Pedido 4 (Total: R$ 4.000,00 - cenário de fronteira R$ 1.999,99)
(4, 'Estação de Trabalho Dupla',   'Escritório', 2, 2000.00),
-- Pedido 5 (Total: R$ 2.800,00)
(5, 'Bancada Banheiro + Espelheira','Banheiro',  1, 2800.00);

-- 6. Pagamentos
INSERT INTO pagamento (pedido_id, data_pagamento, valor_pago, forma_pagamento) VALUES
-- Pedido 1: 100% pago (R$ 3.250 + R$ 3.250 = R$ 6.500)
(1, CURRENT_DATE - 25, 3250.00, 'PIX'),
(1, CURRENT_DATE - 2,  3250.00, 'TRANSFERENCIA'),
-- Pedido 2: 50% pago (R$ 2.600 de R$ 5.200)
(2, CURRENT_DATE - 14, 2600.00, 'PIX'),
-- Pedido 3: R$ 3.500,00 pagos de R$ 4.000,00 (faltam R$ 500 para entregar; tentar pagar R$ 600 falha!)
(3, CURRENT_DATE - 10, 2000.00, 'TRANSFERENCIA'),
(3, CURRENT_DATE - 4,  1500.00, 'CARTAO'),
-- Pedido 4: R$ 1.999,99 pagos de R$ 4.000,00 (1 centavo abaixo dos 50% para testar RN-01!)
(4, CURRENT_DATE - 2,  1999.99, 'DINHEIRO');

-- 7. Compras de Materiais vinculadas aos Pedidos
INSERT INTO compra_material (pedido_id, material_id, fornecedor_id, data_compra, quantidade, custo_unitario) VALUES
                                                                                                                 (1, 1, 1, CURRENT_DATE - 23, 6.000, 240.00),
                                                                                                                 (1, 4, 2, CURRENT_DATE - 23, 8.000,  32.50),
                                                                                                                 (1, 5, 2, CURRENT_DATE - 23, 16.000, 14.00),
                                                                                                                 (2, 2, 1, CURRENT_DATE - 12, 5.000, 310.00),
                                                                                                                 (2, 3, 1, CURRENT_DATE - 12, 2.000, 120.00),
                                                                                                                 (2, 6, 1, CURRENT_DATE - 12, 30.000,  4.50),
                                                                                                                 (3, 1, 1, CURRENT_DATE - 8,  4.000, 240.00),
                                                                                                                 (3, 7, 3, CURRENT_DATE - 8,  1.000,  85.00);