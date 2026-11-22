package br.com.marcenaria;

import java.math.BigDecimal;
import java.sql.*;
import java.time.LocalDate;

public class Main {

    private static final String URL  = System.getenv().getOrDefault("DB_URL",  "jdbc:postgresql://localhost:5432/marcenaria");
    private static final String USER = System.getenv().getOrDefault("DB_USER", "marcenaria");
    private static final String PASS = System.getenv().getOrDefault("DB_PASS", "marcenaria_pwd");

    public static void main(String[] args) {
        System.out.println("=================================================================");
        System.out.println(" PROJETO A3 - MARCENARIA (INTEGRACAO JAVA + POSTGRESQL 17)");
        System.out.println("=================================================================\n");

        try (Connection conn = DriverManager.getConnection(URL, USER, PASS)) {
            conn.setAutoCommit(false); // Controle explícito de transação na aplicação

            // 1. CREATE (CRUD): Cadastra novo cliente, pedido e itens
            int clienteId = inserirCliente(conn, "João Pedro Silva", "987.654.321-99", "(51) 98888-7777", "joao.silva@email.com");
            int pedidoId  = criarPedido(conn, clienteId, LocalDate.now().plusDays(25));
            inserirItemPedido(conn, pedidoId, "Armário Cozinha Planejado", "Cozinha", 1, new BigDecimal("2500.00"));
            inserirItemPedido(conn, pedidoId, "Balcão Pia Granito", "Cozinha", 1, new BigDecimal("1500.00"));
            conn.commit();

            // 2. READ (CRUD + RN-05): Confirma que a trigger recalculou valor_total = R$ 4.000,00
            consultarResumoPedido(conn, pedidoId);

            // 3. TESTE RN-01 (Bloqueio < 50%): Paga R$ 1.999,99 e tenta iniciar produção
            registrarPagamento(conn, pedidoId, new BigDecimal("1999.99"), "PIX");
            conn.commit();
            tentarAvancarStatus(conn, pedidoId, "EM_PRODUCAO", "Deve BLOQUEAR (MARCENARIA-001: < 50%)");

            // 4. TESTE RN-01 (Liberação >= 50%): Completa R$ 0,01 (total R$ 2.000,00) e inicia produção
            registrarPagamento(conn, pedidoId, new BigDecimal("0.01"), "DINHEIRO");
            conn.commit();
            tentarAvancarStatus(conn, pedidoId, "EM_PRODUCAO", "Deve LIBERAR (50% exatos pagos)");

            // 5. Avança produção para PRONTO
            tentarAvancarStatus(conn, pedidoId, "PRONTO", "Deve LIBERAR (EM_PRODUCAO -> PRONTO)");

            // 6. TESTE RN-02 (Teto 100%): Tenta pagar R$ 2.100,00 (excede R$ 4.000,00)
            tentarRegistrarPagamentoInvalido(conn, pedidoId, new BigDecimal("2100.00"), "CARTAO", "Deve BLOQUEAR (MARCENARIA-003: > 100%)");

            // 7. TESTE RN-03 (Entrega exige 100%): Tenta entregar faltando R$ 2.000,00
            tentarAvancarStatus(conn, pedidoId, "ENTREGUE", "Deve BLOQUEAR (MARCENARIA-005: saldo pendente)");

            // 8. Quita os R$ 2.000,00 restantes e conclui entrega
            registrarPagamento(conn, pedidoId, new BigDecimal("2000.00"), "TRANSFERENCIA");
            conn.commit();
            tentarAvancarStatus(conn, pedidoId, "ENTREGUE", "Deve LIBERAR (PRONTO + 100% pago)");

            // 9. Consulta trilha completa de auditoria gerada pela trigger (RN-04)
            listarAuditoriaPedido(conn, pedidoId);

            // 10. UPDATE e DELETE (CRUD): Atualiza telefone do cliente e remove pedido de rascunho
            atualizarTelefoneCliente(conn, clienteId, "(51) 99999-0000");
            int rascunhoId = criarPedido(conn, clienteId, LocalDate.now().plusDays(10));
            excluirPedidoRascunho(conn, rascunhoId);
            conn.commit();

            System.out.println("\n[OK] Todos os fluxos CRUD e regras de negocio validados com sucesso!");

        } catch (SQLException e) {
            System.err.println("Erro fatal de conexao/banco: " + e.getMessage());
        }
    }

    private static int inserirCliente(Connection conn, String nome, String cpf, String tel, String email) throws SQLException {
        String sql = "INSERT INTO cliente (nome, cpf_cnpj, telefone, email) VALUES (?, ?, ?, ?) " +
                "ON CONFLICT (cpf_cnpj) DO UPDATE SET telefone = EXCLUDED.telefone RETURNING cliente_id";
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, nome);
            ps.setString(2, cpf);
            ps.setString(3, tel);
            ps.setString(4, email);
            try (ResultSet rs = ps.executeQuery()) {
                rs.next();
                int id = rs.getInt(1);
                System.out.println("[CRUD - CREATE] Cliente ID=" + id + " (" + nome + ") cadastrado.");
                return id;
            }
        }
    }

    private static int criarPedido(Connection conn, int clienteId, LocalDate entregaPrevista) throws SQLException {
        String sql = "INSERT INTO pedido (cliente_id, data_entrega_prevista) VALUES (?, ?) RETURNING pedido_id";
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, clienteId);
            ps.setDate(2, Date.valueOf(entregaPrevista));
            try (ResultSet rs = ps.executeQuery()) {
                rs.next();
                int id = rs.getInt(1);
                System.out.println("[CRUD - CREATE] Pedido ID=" + id + " criado com status CADASTRADO.");
                return id;
            }
        }
    }

    private static void inserirItemPedido(Connection conn, int pedidoId, String desc, String amb, int qtd, BigDecimal unit) throws SQLException {
        String sql = "INSERT INTO item_pedido (pedido_id, descricao_movel, ambiente, quantidade, valor_unitario) VALUES (?, ?, ?, ?, ?)";
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, pedidoId);
            ps.setString(2, desc);
            ps.setString(3, amb);
            ps.setInt(4, qtd);
            ps.setBigDecimal(5, unit);
            ps.executeUpdate();
        }
    }

    private static void consultarResumoPedido(Connection conn, int pedidoId) throws SQLException {
        String sql = "SELECT p.pedido_id, c.nome, p.status, p.valor_total " +
                "FROM pedido p JOIN cliente c ON c.cliente_id = p.cliente_id WHERE p.pedido_id = ?";
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, pedidoId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    System.out.printf("[CRUD - READ / RN-05] Pedido #%d | Cliente: %s | Status: %s | Valor Total (Trigger): R$ %.2f%n%n",
                            rs.getInt("pedido_id"), rs.getString("nome"), rs.getString("status"), rs.getBigDecimal("valor_total"));
                }
            }
        }
    }

    private static void registrarPagamento(Connection conn, int pedidoId, BigDecimal valor, String forma) throws SQLException {
        try (CallableStatement cs = conn.prepareCall("CALL sp_registrar_pagamento(?, ?, ?)")) {
            cs.setInt(1, pedidoId);
            cs.setBigDecimal(2, valor);
            cs.setString(3, forma);
            cs.execute();
            System.out.printf("[PROCEDURE] Pagamento de R$ %.2f (%s) registrado no Pedido #%d.%n", valor, forma, pedidoId);
        }
    }

    private static void tentarRegistrarPagamentoInvalido(Connection conn, int pedidoId, BigDecimal valor, String forma, String cenario) throws SQLException {
        System.out.println("\n--- Teste: " + cenario + " ---");
        try {
            registrarPagamento(conn, pedidoId, valor, forma);
            conn.commit();
        } catch (SQLException e) {
            conn.rollback();
            System.out.println("[BLOQUEIO ESPERADO] " + e.getMessage());
        }
    }

    private static void tentarAvancarStatus(Connection conn, int pedidoId, String novoStatus, String cenario) throws SQLException {
        System.out.println("\n--- Teste: " + cenario + " ---");
        try (CallableStatement cs = conn.prepareCall("CALL sp_avancar_status_pedido(?, ?)")) {
            cs.setInt(1, pedidoId);
            cs.setString(2, novoStatus);
            cs.execute();
            conn.commit();
            System.out.println("[SUCESSO] Pedido #" + pedidoId + " avancou para -> " + novoStatus);
        } catch (SQLException e) {
            conn.rollback();
            System.out.println("[BLOQUEIO ESPERADO] " + e.getMessage());
        }
    }

    private static void listarAuditoriaPedido(Connection conn, int pedidoId) throws SQLException {
        System.out.println("\n--- Trilha de Auditoria Automatica (RN-04) do Pedido #" + pedidoId + " ---");
        String sql = "SELECT aud_id, COALESCE(status_anterior, '(CRIACAO)') AS de_st, status_novo, usuario_banco, data_hora " +
                "FROM auditoria_pedido WHERE pedido_id = ? ORDER BY aud_id";
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, pedidoId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    System.out.printf("Aud #%d | %s -> %s | Usuario: %s | Data: %s%n",
                            rs.getInt("aud_id"), rs.getString("de_st"), rs.getString("status_novo"),
                            rs.getString("usuario_banco"), rs.getTimestamp("data_hora"));
                }
            }
        }
    }

    private static void atualizarTelefoneCliente(Connection conn, int clienteId, String novoTel) throws SQLException {
        try (PreparedStatement ps = conn.prepareStatement("UPDATE cliente SET telefone = ? WHERE cliente_id = ?")) {
            ps.setString(1, novoTel);
            ps.setInt(2, clienteId);
            ps.executeUpdate();
            System.out.println("\n[CRUD - UPDATE] Telefone do Cliente ID=" + clienteId + " atualizado para " + novoTel);
        }
    }

    private static void excluirPedidoRascunho(Connection conn, int pedidoId) throws SQLException {
        try (PreparedStatement ps = conn.prepareStatement("DELETE FROM pedido WHERE pedido_id = ?")) {
            ps.setInt(1, pedidoId);
            ps.executeUpdate();
            System.out.println("[CRUD - DELETE] Pedido rascunho ID=" + pedidoId + " removido com sucesso.");
        }
    }
}